import Foundation

// MARK: - Types

/// Reason for process termination
public enum TerminationReason: Sendable, Equatable {
    case exit               // Normal exit
    case signal(Int32)      // Killed by signal
    case timeout            // Our timeout fired
    case startFailed        // process.run() threw
}

/// Result of running a command
public struct CommandResult: Sendable {
    public let exitCode: Int32?
    public let terminationStatus: Int32?
    public let stdout: Data
    public let stderr: Data
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let outputMayBeIncomplete: Bool
    public let reason: TerminationReason
}

/// Configuration for ProcessRunner
public struct ProcessRunnerConfig: Sendable {
    public let allowedExecutables: Set<String>
    public let requireCodesign: Bool
    public let maxOutputSize: Int
    public let timeout: TimeInterval
    
    public static let production = ProcessRunnerConfig(
        allowedExecutables: [
            "/usr/bin/dscacheutil",
            "/usr/bin/killall",
            "/usr/bin/mdutil",
            "/usr/sbin/purge",
            "/usr/bin/atsutil"
        ],
        requireCodesign: true,
        maxOutputSize: 10 * 1024 * 1024,
        timeout: 30.0
    )
    
    public static let testing = ProcessRunnerConfig(
        allowedExecutables: [
            "/usr/bin/dscacheutil",
            "/usr/bin/killall",
            "/usr/bin/mdutil",
            "/usr/sbin/purge",
            "/usr/bin/atsutil",
            "/usr/bin/python3",
            "/bin/cat",
            "/bin/sleep",
            "/bin/echo"
        ],
        requireCodesign: false,
        maxOutputSize: 256 * 1024,
        timeout: 5.0
    )
    
    public init(allowedExecutables: Set<String>, requireCodesign: Bool, maxOutputSize: Int, timeout: TimeInterval) {
        self.allowedExecutables = Set(allowedExecutables.map { Self.canonicalize($0) })
        self.requireCodesign = requireCodesign
        self.maxOutputSize = maxOutputSize
        self.timeout = timeout
    }
    
    public static func canonicalize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}

// MARK: - ProcessRunner

/// Production-grade process runner with pipe handling, timeout, and safety
public final class ProcessRunner: @unchecked Sendable {
    private let config: ProcessRunnerConfig
    
    public init(config: ProcessRunnerConfig = .production) {
        self.config = config
    }
    
    // MARK: - Public API
    
    public func run(executable: String, arguments: [String]) async -> CommandResult {
        // Canonicalize and validate
        let canonicalPath = ProcessRunnerConfig.canonicalize(executable)
        guard config.allowedExecutables.contains(canonicalPath) else {
            return CommandResult(
                exitCode: nil, terminationStatus: nil,
                stdout: Data(), stderr: Data(),
                stdoutTruncated: false, stderrTruncated: false,
                outputMayBeIncomplete: false,
                reason: .startFailed
            )
        }
        
        // Codesign check (if enabled)
        if config.requireCodesign && !Self.verifyCodesign(path: canonicalPath) {
            return CommandResult(
                exitCode: nil, terminationStatus: nil,
                stdout: Data(), stderr: Data(),
                stdoutTruncated: false, stderrTruncated: false,
                outputMayBeIncomplete: false,
                reason: .startFailed
            )
        }
        
        return await withCheckedContinuation { continuation in
            runProcess(executable: canonicalPath, arguments: arguments) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func runProcess(executable: String, arguments: [String], completion: @escaping (CommandResult) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.environment = [:] // Minimal environment
        
        // Pipes
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // State (protected by lock)
        let lock = NSLock()
        var isTimedOut = false
        var isFinished = false
        var stdoutData = Data()
        var stderrData = Data()
        var stdoutTruncated = false
        var stderrTruncated = false
        var outputMayBeIncomplete = false
        var reason: TerminationReason = .exit
        var terminationStatus: Int32? = nil
        
        // Reserve capacity
        stdoutData.reserveCapacity(config.maxOutputSize)
        stderrData.reserveCapacity(config.maxOutputSize)
        
        let group = DispatchGroup()
        var stdoutEntered = false
        var stderrEntered = false
        var stdoutLeft = false
        var stderrLeft = false
        
        // leaveOnce helpers
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
        
        // finishOnce
        func finishOnce(_ newReason: TerminationReason, incomplete: Bool = false) {
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                return
            }
            isFinished = true
            if newReason == .timeout { isTimedOut = true }
            if !isTimedOut || (reason != .timeout) { reason = newReason }
            if incomplete { outputMayBeIncomplete = true }
            lock.unlock()
            
            // Force close pipes
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            
            leaveOnceStdout()
            leaveOnceStderr()
        }
        
        // Pump setup
        let maxSize = config.maxOutputSize
        
        group.enter()
        stdoutEntered = true
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard self != nil else { return }
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                leaveOnceStdout()
            } else {
                lock.lock()
                let timedOut = isTimedOut
                if !timedOut && stdoutData.count < maxSize {
                    let remaining = maxSize - stdoutData.count
                    if data.count <= remaining {
                        stdoutData.append(data)
                    } else {
                        stdoutData.append(data.prefix(remaining))
                        stdoutTruncated = true
                    }
                } else if !stdoutTruncated && stdoutData.count >= maxSize {
                    stdoutTruncated = true
                }
                lock.unlock()
            }
        }
        
        group.enter()
        stderrEntered = true
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard self != nil else { return }
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                leaveOnceStderr()
            } else {
                lock.lock()
                let timedOut = isTimedOut
                if !timedOut && stderrData.count < maxSize {
                    let remaining = maxSize - stderrData.count
                    if data.count <= remaining {
                        stderrData.append(data)
                    } else {
                        stderrData.append(data.prefix(remaining))
                        stderrTruncated = true
                    }
                } else if !stderrTruncated && stderrData.count >= maxSize {
                    stderrTruncated = true
                }
                lock.unlock()
            }
        }
        
        // Timeout timer
        let timeoutTimer = DispatchSource.makeTimerSource(queue: .global())
        timeoutTimer.schedule(deadline: .now() + config.timeout)
        timeoutTimer.setEventHandler {
            finishOnce(.timeout, incomplete: true)
            process.terminate()
            
            // Grace period then SIGKILL
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        timeoutTimer.resume()
        
        // Termination handler (set before run)
        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { proc in
            terminationStatus = proc.terminationStatus
            exitSemaphore.signal()
        }
        
        // Start process
        do {
            try process.run()
        } catch {
            timeoutTimer.cancel()
            finishOnce(.startFailed)
            
            lock.lock()
            let result = CommandResult(
                exitCode: nil, terminationStatus: nil,
                stdout: stdoutData, stderr: stderrData,
                stdoutTruncated: stdoutTruncated, stderrTruncated: stderrTruncated,
                outputMayBeIncomplete: true,
                reason: .startFailed
            )
            lock.unlock()
            completion(result)
            return
        }
        
        // Wait for process exit (bounded)
        DispatchQueue.global().async {
            let exitTimeout = DispatchTime.now() + min(2.0, self.config.timeout)
            let waitResult = exitSemaphore.wait(timeout: exitTimeout)
            
            timeoutTimer.cancel()
            
            // If semaphore timed out or process still running, it's a timeout case
            if waitResult == .timedOut || process.isRunning {
                finishOnce(.timeout, incomplete: true)
                if process.isRunning {
                    process.terminate()
                    usleep(200_000) // 0.2s grace
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            } else {
                // Process exited normally - safe to access termination properties
                lock.lock()
                if !isFinished {
                    isFinished = true
                    terminationStatus = process.terminationStatus
                    if process.terminationReason == .uncaughtSignal {
                        // Only update to signal if we didn't already set timeout
                        if reason != .timeout {
                            reason = .signal(process.terminationStatus)
                        }
                    }
                }
                lock.unlock()
            }
            
            // Wait for pipes to drain (bounded)
            let drainTimeout = DispatchTime.now() + min(1.0, self.config.timeout)
            let drainResult = group.wait(timeout: drainTimeout)
            if drainResult == .timedOut {
                finishOnce(reason, incomplete: true)
            } else {
                // Normal cleanup if not already finished
                lock.lock()
                let alreadyFinished = isFinished
                lock.unlock()
                if !alreadyFinished {
                    finishOnce(reason, incomplete: false)
                }
            }
            
            // Build result
            lock.lock()
            let finalExitCode: Int32?
            if reason == .exit {
                finalExitCode = terminationStatus
            } else if case .signal = reason {
                finalExitCode = terminationStatus
            } else {
                finalExitCode = nil
            }
            let result = CommandResult(
                exitCode: finalExitCode,
                terminationStatus: terminationStatus,
                stdout: stdoutData,
                stderr: stderrData,
                stdoutTruncated: stdoutTruncated,
                stderrTruncated: stderrTruncated,
                outputMayBeIncomplete: outputMayBeIncomplete,
                reason: reason
            )
            lock.unlock()
            
            completion(result)
        }
    }
    
    // MARK: - Security
    
    private static func verifyCodesign(path: String) -> Bool {
        // Use SecStaticCode to verify anchor apple
        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return false
        }
        
        // anchor apple requirement
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else {
            return false
        }
        
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
