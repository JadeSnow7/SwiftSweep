import Foundation

/// SwiftSweep Privileged Helper Tool
/// 运行在 root 权限下，通过 XPC 接收主程序的命令

let helperIdentifier = "com.swiftsweep.helper"

// 设置 XPC 监听
let listener = NSXPCListener(machServiceName: helperIdentifier)
let delegate = HelperDelegate()
listener.delegate = delegate
listener.resume()

// 保持运行
RunLoop.main.run()

// MARK: - XPC Delegate

class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // 配置连接，接口需与客户端的 HelperXPCProtocol 完全一致
        newConnection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        newConnection.exportedObject = HelperService()
        
        // 设置无效处理
        newConnection.invalidationHandler = {
            // 连接关闭时的清理
        }
        
        newConnection.resume()
        return true
    }
}

// MARK: - Helper Protocol

@objc protocol HelperXPCProtocol {
    func flushDNS(withReply reply: @escaping (Bool, String) -> Void)
    func rebuildSpotlight(withReply reply: @escaping (Bool, String) -> Void)
    func clearMemory(withReply reply: @escaping (Bool, String) -> Void)
    func deleteFile(atPath path: String, withReply reply: @escaping (Bool, String) -> Void)
    func runCommand(_ command: String, arguments: [String], withReply reply: @escaping (Bool, String) -> Void)
    func getVersion(withReply reply: @escaping (String) -> Void)
}

// MARK: - Helper Service Implementation

class HelperService: NSObject, HelperXPCProtocol {
    
    func flushDNS(withReply reply: @escaping (Bool, String) -> Void) {
        let result = runShellCommand("/usr/bin/dscacheutil", arguments: ["-flushcache"])
        // 还需要运行 killall -HUP mDNSResponder
        let result2 = runShellCommand("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
        reply(result.0 && result2.0, result.1 + "\n" + result2.1)
    }
    
    func rebuildSpotlight(withReply reply: @escaping (Bool, String) -> Void) {
        let result = runShellCommand("/usr/bin/mdutil", arguments: ["-E", "/"])
        reply(result.0, result.1)
    }
    
    func clearMemory(withReply reply: @escaping (Bool, String) -> Void) {
        let result = runShellCommand("/usr/sbin/purge", arguments: [])
        reply(result.0, result.1)
    }
    
    func deleteFile(atPath path: String, withReply reply: @escaping (Bool, String) -> Void) {
        do {
            try safeDelete(at: path)
            reply(true, "Deleted: \(path)")
        } catch let error as HelperError {
            reply(false, "Error \(error.rawValue): \(error.description)")
        } catch {
            reply(false, "Unknown error: \(error.localizedDescription)")
        }
    }
    
    private func safeDelete(at path: String) throws {
        // 1. Normalize and validate path
        guard let norm = CleanupAllowlist.normalize(path),
              CleanupAllowlist.isTargetAllowed(norm) else {
            throw HelperError.notAllowedPath
        }
        
        let url = URL(fileURLWithPath: norm)
        let parent = url.deletingLastPathComponent().path
        let name = url.lastPathComponent
        
        // 2. Get canonical parent path
        let parentRealPtr = realpath(parent, nil)
        defer { free(parentRealPtr) }
        guard let ptr = parentRealPtr else {
            throw HelperError.fromErrno(errno)
        }
        let parentReal = String(cString: ptr)
        
        // 3. Verify parent is within allowed root
        guard CleanupAllowlist.isParentAllowed(parentReal) else {
            throw HelperError.symlinkEscape
        }
        
        // 4. Open canonicalized parent directory
        let dirFD = open(parentReal, O_RDONLY | O_DIRECTORY)
        guard dirFD >= 0 else {
            throw HelperError.fromErrno(errno)
        }
        defer { close(dirFD) }
        
        // 5. Check file status (immutable, type)
        var st = stat()
        guard fstatat(dirFD, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw HelperError.fromErrno(errno)
        }
        
        // Check immutable flags
        let immutableFlags = UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)
        if (st.st_flags & immutableFlags) != 0 {
            throw HelperError.immutableFile
        }
        
        // 6. Delete using unlinkat
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        let flags: Int32 = isDir ? AT_REMOVEDIR : 0
        guard unlinkat(dirFD, name, flags) == 0 else {
            throw HelperError.fromErrno(errno)
        }
    }
    
    func runCommand(_ command: String, arguments: [String], withReply reply: @escaping (Bool, String) -> Void) {
        let result = runShellCommand(command, arguments: arguments)
        reply(result.0, result.1)
    }
    
    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }
    
    // MARK: - Private
    
    /// Robust shell command runner with pipe handling and timeout
    private func runShellCommand(_ command: String, arguments: [String], timeout: TimeInterval = 30.0) -> (Bool, String) {
        // Allowlist check
        let allowedCommands: Set<String> = [
            "/usr/bin/dscacheutil",
            "/usr/bin/killall",
            "/usr/bin/mdutil",
            "/usr/sbin/purge",
            "/usr/bin/atsutil"
        ]
        
        let canonicalPath = URL(fileURLWithPath: command).resolvingSymlinksInPath().path
        guard allowedCommands.contains(canonicalPath) else {
            return (false, "Command not in allowlist: \(command)")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: canonicalPath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.environment = [:] // Minimal environment
        
        // Pipes
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // State
        let lock = NSLock()
        var isTimedOut = false
        var isFinished = false
        var stdoutData = Data()
        var stderrData = Data()
        let maxSize = 10 * 1024 * 1024 // 10MB limit
        
        let group = DispatchGroup()
        var stdoutEntered = false, stderrEntered = false
        var stdoutLeft = false, stderrLeft = false
        
        func leaveOnceStdout() {
            lock.lock()
            let shouldLeave = stdoutEntered && !stdoutLeft
            if shouldLeave { stdoutLeft = true }
            lock.unlock()
            if shouldLeave { group.leave() }
        }
        
        func leaveOnceStderr() {
            lock.lock()
            let shouldLeave = stderrEntered && !stderrLeft
            if shouldLeave { stderrLeft = true }
            lock.unlock()
            if shouldLeave { group.leave() }
        }
        
        func finishOnce() {
            lock.lock()
            guard !isFinished else { lock.unlock(); return }
            isFinished = true
            lock.unlock()
            
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            
            leaveOnceStdout()
            leaveOnceStderr()
        }
        
        // Setup pipe handlers
        group.enter()
        stdoutEntered = true
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                leaveOnceStdout()
            } else {
                lock.lock()
                if !isTimedOut && stdoutData.count < maxSize {
                    let remaining = maxSize - stdoutData.count
                    stdoutData.append(data.prefix(remaining))
                }
                lock.unlock()
            }
        }
        
        group.enter()
        stderrEntered = true
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                leaveOnceStderr()
            } else {
                lock.lock()
                if !isTimedOut && stderrData.count < maxSize {
                    let remaining = maxSize - stderrData.count
                    stderrData.append(data.prefix(remaining))
                }
                lock.unlock()
            }
        }
        
        // Timeout timer
        let timeoutTimer = DispatchSource.makeTimerSource(queue: .global())
        timeoutTimer.schedule(deadline: .now() + timeout)
        timeoutTimer.setEventHandler {
            lock.lock()
            isTimedOut = true
            lock.unlock()
            finishOnce()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        timeoutTimer.resume()
        
        // Termination handler
        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitSemaphore.signal()
        }
        
        // Start process
        do {
            try process.run()
        } catch {
            timeoutTimer.cancel()
            finishOnce()
            return (false, "Failed to start: \(error.localizedDescription)")
        }
        
        // Wait for exit (bounded)
        let waitResult = exitSemaphore.wait(timeout: .now() + min(timeout + 2, 60))
        timeoutTimer.cancel()
        
        if waitResult == .timedOut || process.isRunning {
            lock.lock()
            isTimedOut = true
            lock.unlock()
            finishOnce()
            if process.isRunning {
                process.terminate()
                usleep(200_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        
        // Wait for pipes (bounded)
        _ = group.wait(timeout: .now() + 1.0)
        finishOnce()
        
        // Build result
        lock.lock()
        let timedOut = isTimedOut
        let stdout = stdoutData
        let stderr = stderrData
        lock.unlock()
        
        if timedOut {
            return (false, "Command timed out")
        }
        
        let output = String(data: stdout, encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr, encoding: .utf8) ?? ""
        let combined = output + (errorOutput.isEmpty ? "" : "\n" + errorOutput)
        
        return (process.terminationStatus == 0, combined)
    }
}
