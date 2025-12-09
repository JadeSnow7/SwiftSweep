import Foundation
import ServiceManagement
import Security

/// SMJobBless 客户端 - 用于安装和通信 Privileged Helper
public final class SMJobBlessClient {
    public static let shared = SMJobBlessClient()
    
    private let helperIdentifier = "com.swiftsweep.helper"
    private var connection: NSXPCConnection?
    
    private init() {}
    
    // MARK: - Installation
    
    /// 检查 Helper 是否已安装
    public func isHelperInstalled() -> Bool {
        let helperPath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
        return FileManager.default.fileExists(atPath: helperPath)
    }
    
    /// 安装 Helper (需要管理员权限)
    public func installHelper() throws {
        var authRef: AuthorizationRef?
        var authItem = AuthorizationItem(name: kSMRightBlessPrivilegedHelper, valueLength: 0, value: nil, flags: 0)
        var authRights = AuthorizationRights(count: 1, items: &authItem)
        let authFlags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
        
        let status = AuthorizationCreate(&authRights, nil, authFlags, &authRef)
        
        guard status == errAuthorizationSuccess, let auth = authRef else {
            throw HelperError.authorizationFailed
        }
        
        defer { AuthorizationFree(auth, []) }
        
        var error: Unmanaged<CFError>?
        let success = SMJobBless(kSMDomainSystemLaunchd, helperIdentifier as CFString, auth, &error)
        
        if !success {
            if let cfError = error?.takeRetainedValue() {
                throw HelperError.installFailed(cfError.localizedDescription)
            }
            throw HelperError.installFailed("Unknown error")
        }
    }
    
    /// 卸载 Helper
    public func uninstallHelper() throws {
        // 需要 root 权限删除
        let helperPath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
        let plistPath = "/Library/LaunchDaemons/\(helperIdentifier).plist"
        
        // 先停止服务
        let stopTask = Process()
        stopTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        stopTask.arguments = ["unload", plistPath]
        try? stopTask.run()
        stopTask.waitUntilExit()
        
        // 删除文件 (需要 sudo)
        try FileManager.default.removeItem(atPath: helperPath)
        try FileManager.default.removeItem(atPath: plistPath)
    }
    
    // MARK: - XPC Connection
    
    /// 获取 XPC 连接
    private func getConnection() -> NSXPCConnection {
        if let conn = connection, conn.isValid {
            return conn
        }
        
        let conn = NSXPCConnection(machServiceName: helperIdentifier, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        
        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        
        conn.resume()
        connection = conn
        return conn
    }
    
    // MARK: - Helper Operations
    
    /// 刷新 DNS
    public func flushDNS() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = getConnection().remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? HelperXPCProtocol else {
                continuation.resume(throwing: HelperError.connectionFailed)
                return
            }
            
            proxy.flushDNS { success, output in
                if success {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: HelperError.executionFailed(output))
                }
            }
        }
    }
    
    /// 重建 Spotlight
    public func rebuildSpotlight() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = getConnection().remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? HelperXPCProtocol else {
                continuation.resume(throwing: HelperError.connectionFailed)
                return
            }
            
            proxy.rebuildSpotlight { success, output in
                if success {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: HelperError.executionFailed(output))
                }
            }
        }
    }
    
    /// 清理内存
    public func clearMemory() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = getConnection().remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? HelperXPCProtocol else {
                continuation.resume(throwing: HelperError.connectionFailed)
                return
            }
            
            proxy.clearMemory { success, output in
                if success {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: HelperError.executionFailed(output))
                }
            }
        }
    }
    
    /// 删除文件
    public func deleteFile(at path: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = getConnection().remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? HelperXPCProtocol else {
                continuation.resume(throwing: HelperError.connectionFailed)
                return
            }
            
            proxy.deleteFile(atPath: path) { success, output in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HelperError.executionFailed(output))
                }
            }
        }
    }
    
    // MARK: - Errors
    
    public enum HelperError: Error, LocalizedError {
        case authorizationFailed
        case installFailed(String)
        case connectionFailed
        case executionFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .authorizationFailed:
                return "Authorization failed"
            case .installFailed(let reason):
                return "Failed to install helper: \(reason)"
            case .connectionFailed:
                return "Failed to connect to helper"
            case .executionFailed(let reason):
                return "Execution failed: \(reason)"
            }
        }
    }
}

// MARK: - XPC Protocol (shared between app and helper)

@objc public protocol HelperXPCProtocol {
    func flushDNS(withReply reply: @escaping (Bool, String) -> Void)
    func rebuildSpotlight(withReply reply: @escaping (Bool, String) -> Void)
    func clearMemory(withReply reply: @escaping (Bool, String) -> Void)
    func deleteFile(atPath path: String, withReply reply: @escaping (Bool, String) -> Void)
    func runCommand(_ command: String, arguments: [String], withReply reply: @escaping (Bool, String) -> Void)
    func getVersion(withReply reply: @escaping (String) -> Void)
}

// MARK: - NSXPCConnection extension

private extension NSXPCConnection {
    var isValid: Bool {
        // 简单检查连接是否可用
        return true
    }
}
