import Foundation
import ServiceManagement

/// SwiftSweep 权限助手客户端
/// 使用 SMAppService (macOS 13+) 管理特权助手
@available(macOS 13.0, *)
public final class HelperClient {
    public static let shared = HelperClient()
    
    private let helperBundleIdentifier = "com.swiftsweep.helper"
    
    public enum HelperError: Error, LocalizedError {
        case notInstalled
        case installationFailed(String)
        case communicationFailed(String)
        case executionFailed(String)
        case unauthorized
        
        public var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Privileged helper is not installed"
            case .installationFailed(let reason):
                return "Failed to install helper: \(reason)"
            case .communicationFailed(let reason):
                return "Communication with helper failed: \(reason)"
            case .executionFailed(let reason):
                return "Command execution failed: \(reason)"
            case .unauthorized:
                return "User authorization required"
            }
        }
    }
    
    public enum HelperStatus {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
    }
    
    private init() {}
    
    // MARK: - Helper Management
    
    /// 检查 Helper 状态
    public func checkStatus() -> HelperStatus {
        let service = SMAppService.daemon(plistName: "\(helperBundleIdentifier).plist")
        
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }
    
    /// 注册 Helper (需要用户在系统设置中批准)
    public func registerHelper() async throws {
        let service = SMAppService.daemon(plistName: "\(helperBundleIdentifier).plist")
        
        do {
            try service.register()
        } catch {
            throw HelperError.installationFailed(error.localizedDescription)
        }
    }
    
    /// 注销 Helper
    public func unregisterHelper() async throws {
        let service = SMAppService.daemon(plistName: "\(helperBundleIdentifier).plist")
        
        do {
            try await service.unregister()
        } catch {
            throw HelperError.installationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Privileged Operations
    
    /// 刷新 DNS 缓存
    public func flushDNS() async throws -> String {
        guard checkStatus() == .enabled else {
            throw HelperError.notInstalled
        }
        
        return try await runPrivilegedCommand("/usr/bin/dscacheutil", arguments: ["-flushcache"])
    }
    
    /// 重建 Spotlight 索引
    public func rebuildSpotlight() async throws -> String {
        guard checkStatus() == .enabled else {
            throw HelperError.notInstalled
        }
        
        return try await runPrivilegedCommand("/usr/bin/mdutil", arguments: ["-E", "/"])
    }
    
    /// 清理内存
    public func purgeMemory() async throws -> String {
        guard checkStatus() == .enabled else {
            throw HelperError.notInstalled
        }
        
        return try await runPrivilegedCommand("/usr/sbin/purge", arguments: [])
    }
    
    /// 删除需要权限的文件
    public func deleteFile(at path: String) async throws {
        guard checkStatus() == .enabled else {
            throw HelperError.notInstalled
        }
        
        _ = try await runPrivilegedCommand("/bin/rm", arguments: ["-rf", path])
    }
    
    // MARK: - Private
    
    private func runPrivilegedCommand(_ command: String, arguments: [String]) async throws -> String {
        // 注意: 实际的 XPC 通信需要 Helper 进程
        // 这里是占位实现，完整实现需要:
        // 1. Helper 进程运行并监听 XPC
        // 2. 主程序通过 XPC 发送命令
        // 3. Helper 执行并返回结果
        
        // 临时实现: 对于不需要 root 的命令，直接运行
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            throw HelperError.executionFailed(output)
        }
        
        return output
    }
}

// MARK: - Backwards Compatibility

/// 为 macOS 12 及更早版本提供兼容层
public final class LegacyHelperClient {
    public static let shared = LegacyHelperClient()
    
    private init() {}
    
    public func isAvailable() -> Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }
    
    public func runWithAuthorizationPrompt(_ command: String, arguments: [String]) async throws -> String {
        // 使用 AppleScript 提示用户输入密码
        let fullCommand = ([command] + arguments).joined(separator: " ")
        let script = """
        do shell script "\(fullCommand)" with administrator privileges
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if let error = error {
                throw NSError(domain: "AppleScriptError", code: -1, userInfo: error as? [String: Any])
            }
            return result.stringValue ?? ""
        }
        
        throw NSError(domain: "AppleScriptError", code: -1, userInfo: nil)
    }
}
