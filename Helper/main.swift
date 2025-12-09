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
        // 配置连接
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
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

@objc protocol HelperProtocol {
    func flushDNS(withReply reply: @escaping (Bool, String) -> Void)
    func rebuildSpotlight(withReply reply: @escaping (Bool, String) -> Void)
    func clearMemory(withReply reply: @escaping (Bool, String) -> Void)
    func deleteFile(atPath path: String, withReply reply: @escaping (Bool, String) -> Void)
    func runCommand(_ command: String, arguments: [String], withReply reply: @escaping (Bool, String) -> Void)
    func getVersion(withReply reply: @escaping (String) -> Void)
}

// MARK: - Helper Service Implementation

class HelperService: NSObject, HelperProtocol {
    
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
        // 安全检查：不允许删除系统关键目录
        let forbiddenPaths = ["/System", "/usr", "/bin", "/sbin", "/Applications", "/Library"]
        for forbidden in forbiddenPaths {
            if path.hasPrefix(forbidden) && !path.contains("/Caches/") && !path.contains("/Logs/") {
                reply(false, "Cannot delete protected path: \(path)")
                return
            }
        }
        
        let result = runShellCommand("/bin/rm", arguments: ["-rf", path])
        reply(result.0, result.1)
    }
    
    func runCommand(_ command: String, arguments: [String], withReply reply: @escaping (Bool, String) -> Void) {
        let result = runShellCommand(command, arguments: arguments)
        reply(result.0, result.1)
    }
    
    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }
    
    // MARK: - Private
    
    private func runShellCommand(_ command: String, arguments: [String]) -> (Bool, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return (process.terminationStatus == 0, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
