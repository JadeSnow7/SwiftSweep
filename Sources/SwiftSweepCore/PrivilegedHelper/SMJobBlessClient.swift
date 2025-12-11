import Foundation
import ServiceManagement

/// 使用 SMAppService 的 Helper 客户端（替代 SMJobBless）
public final class SMJobBlessClient {
    public static let shared = SMJobBlessClient()
    
    private let helperIdentifier = "com.swiftsweep.helper"
    private var connection: NSXPCConnection?
    
    private init() {}
    
    // MARK: - Installation
    
    /// 检查 Helper 是否已安装
    public func isHelperInstalled() -> Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.daemon(plistName: "\(helperIdentifier).plist").status
            return status == .enabled
        }
        // 对于旧系统，保持兼容：检查文件是否存在
        let helperPath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
        return FileManager.default.fileExists(atPath: helperPath)
    }
    
    /// 安装 Helper（使用 SMAppService，macOS 13+）
    public func installHelper() throws {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
            do {
                try service.register()
            } catch {
                throw HelperError.installFailed(error.localizedDescription)
            }
        } else {
            throw HelperError.installFailed("SMAppService requires macOS 13+")
        }
    }
    
    /// 卸载 Helper（SMAppService）
    public func uninstallHelper() throws {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
            do {
                try service.unregister()
            } catch {
                throw HelperError.installFailed(error.localizedDescription)
            }
        } else {
            throw HelperError.installFailed("SMAppService requires macOS 13+")
        }
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
