import Foundation
import ServiceManagement

/// SwiftSweep 权限助手客户端
/// 使用 SMAppService (macOS 13+) 管理特权助手
@available(macOS 13.0, *)
public final class HelperClient {
    public static let shared = HelperClient()
    
    private let helperBundleIdentifier = "com.swiftsweep.helper"
    private var connection: NSXPCConnection?
    
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
    
    // MARK: - XPC Connection
    
    private func getConnection() throws -> NSXPCConnection {
        if let conn = connection {
            return conn
        }
        
        let conn = NSXPCConnection(machServiceName: helperBundleIdentifier, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        
        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        
        conn.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        
        conn.resume()
        connection = conn
        return conn
    }
    
    // MARK: - Privileged Operations
    
    /// 刷新 DNS 缓存
    public func flushDNS() async throws -> String {
        guard checkStatus() == .enabled else {
            throw HelperError.notInstalled
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let conn = try getConnection()
                guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                    continuation.resume(throwing: HelperError.communicationFailed(error.localizedDescription))
                }) as? HelperXPCProtocol else {
                    continuation.resume(throwing: HelperError.communicationFailed("Failed to get proxy"))
                    return
                }
                
                proxy.flushDNS { success, output in
                    if success {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: HelperError.executionFailed(output))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// 重建 Spotlight 索引
    public func rebuildSpotlight() async throws -> String {
        guard checkStatus() == .enabled else {
            throw HelperError.notInstalled
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let conn = try getConnection()
                guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                    continuation.resume(throwing: HelperError.communicationFailed(error.localizedDescription))
                }) as? HelperXPCProtocol else {
                    continuation.resume(throwing: HelperError.communicationFailed("Failed to get proxy"))
                    return
                }
                
                proxy.rebuildSpotlight { success, output in
                    if success {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: HelperError.executionFailed(output))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// 清理内存
    public func purgeMemory() async throws -> String {
        guard checkStatus() == .enabled else {
            throw HelperError.notInstalled
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let conn = try getConnection()
                guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                    continuation.resume(throwing: HelperError.communicationFailed(error.localizedDescription))
                }) as? HelperXPCProtocol else {
                    continuation.resume(throwing: HelperError.communicationFailed("Failed to get proxy"))
                    return
                }
                
                proxy.clearMemory { success, output in
                    if success {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: HelperError.executionFailed(output))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// 清理字体缓存
    public func clearFontCache() async throws -> String {
        guard checkStatus() == .enabled else {
            throw HelperError.notInstalled
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let conn = try getConnection()
                guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                    continuation.resume(throwing: HelperError.communicationFailed(error.localizedDescription))
                }) as? HelperXPCProtocol else {
                    continuation.resume(throwing: HelperError.communicationFailed("Failed to get proxy"))
                    return
                }
                
                proxy.runCommand("/usr/bin/atsutil", arguments: ["databases", "-remove"]) { success, output in
                    if success {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: HelperError.executionFailed(output))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// 删除需要权限的文件
    public func deleteFile(at path: String) async throws {
        guard checkStatus() == .enabled else {
            throw HelperError.notInstalled
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let conn = try getConnection()
                guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                    continuation.resume(throwing: HelperError.communicationFailed(error.localizedDescription))
                }) as? HelperXPCProtocol else {
                    continuation.resume(throwing: HelperError.communicationFailed("Failed to get proxy"))
                    return
                }
                
                proxy.deleteFile(atPath: path) { success, output in
                    if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: HelperError.executionFailed(output))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
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
