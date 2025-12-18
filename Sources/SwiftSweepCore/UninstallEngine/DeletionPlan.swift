import Foundation
import Logging

// MARK: - Deletion Types

/// 待删除项的类型
public enum DeletionItemKind: String, Codable {
    case app = "App"
    case cache = "Cache"
    case preferences = "Preferences"
    case appSupport = "Application Support"
    case launchAgent = "Launch Agent"
    case container = "Container"
    case other = "Other"
    
    init(from residualType: UninstallEngine.ResidualType) {
        switch residualType {
        case .cache: self = .cache
        case .preferences: self = .preferences
        case .appSupport: self = .appSupport
        case .launchAgent: self = .launchAgent
        case .container: self = .container
        case .other: self = .other
        }
    }
}

/// 单个待删除项
public struct DeletionItem: Identifiable, Hashable {
    public let id: UUID
    public let path: String
    public let resolvedPath: String  // 解析符号链接后的真实路径
    public let kind: DeletionItemKind
    public let size: Int64
    
    public init(path: String, resolvedPath: String, kind: DeletionItemKind, size: Int64) {
        self.id = UUID()
        self.path = path
        self.resolvedPath = resolvedPath
        self.kind = kind
        self.size = size
    }
}

/// 删除项执行结果
public struct DeletionItemResult: Identifiable {
    public let id: UUID
    public let item: DeletionItem
    public let success: Bool
    public let error: String?
    
    public init(item: DeletionItem, success: Bool, error: String? = nil) {
        self.id = item.id
        self.item = item
        self.success = success
        self.error = error
    }
}

/// 删除计划
public struct DeletionPlan {
    public let app: UninstallEngine.InstalledApp
    public let items: [DeletionItem]
    
    public var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }
    
    public var allPaths: [String] {
        items.map { $0.path }
    }
}

/// 删除执行结果
public struct DeletionResult {
    public let itemResults: [DeletionItemResult]
    
    public init(itemResults: [DeletionItemResult]) {
        self.itemResults = itemResults
    }
    
    public var successCount: Int {
        itemResults.filter { $0.success }.count
    }
    
    public var failureCount: Int {
        itemResults.filter { !$0.success }.count
    }
    
    public var isComplete: Bool {
        failureCount == 0
    }
    
    public var failedItems: [DeletionItem] {
        itemResults.filter { !$0.success }.map { $0.item }
    }
}

// MARK: - Path Validation

public enum PathValidationError: Error, LocalizedError {
    case pathNotAllowed(String)
    case systemPathBlocked(String)
    case appleAppBlocked(String)
    case symlinkEscape(original: String, resolved: String)
    case pathNotExists(String)
    
    public var errorDescription: String? {
        switch self {
        case .pathNotAllowed(let path):
            return "Path not in allowed locations: \(path)"
        case .systemPathBlocked(let path):
            return "System path cannot be deleted: \(path)"
        case .appleAppBlocked(let path):
            return "Apple system app cannot be deleted: \(path)"
        case .symlinkEscape(let original, let resolved):
            return "Symlink escape detected: \(original) -> \(resolved)"
        case .pathNotExists(let path):
            return "Path does not exist: \(path)"
        }
    }
}

/// 路径验证器 - App 侧验证
public struct PathValidator {
    
    /// 允许删除的路径前缀白名单
    private static let allowedPrefixes: [String] = {
        let home = NSHomeDirectory()
        return [
            "/Applications/",
            "\(home)/Applications/",
            "\(home)/Library/Caches/",
            "\(home)/Library/Preferences/",
            "\(home)/Library/Application Support/",
            "\(home)/Library/LaunchAgents/",
            "\(home)/Library/Containers/",
            "\(home)/Library/Logs/",
            "\(home)/Library/Saved Application State/",
        ]
    }()
    
    /// 绝对禁止删除的路径前缀
    private static let blockedPrefixes: [String] = [
        "/System/",
        "/System/Applications/",
        "/usr/",
        "/bin/",
        "/sbin/",
        "/private/var/",
        "/Library/",  // 系统级 Library
    ]
    
    /// 禁止删除的 Bundle ID 前缀 (已废弃，改用路径判定)
    // private static let blockedBundleIDPrefixes: [String] = ["com.apple."]
    
    /// Apple App Bundle ID 前缀 (需设置开关 + 二次确认)
    private static let appleAppBundleIDPrefix = "com.apple."
    
    /// 检查是否为 Apple App（需设置开关 + 二次确认，但不阻止删除）
    /// - Returns: true 如果是 Apple 官方应用
    public static func isAppleApp(_ app: UninstallEngine.InstalledApp) -> Bool {
        app.bundleID.lowercased().hasPrefix(appleAppBundleIDPrefix)
    }
    
    /// 检查是否为系统只读卷上的 App（永远禁止删除）
    /// - Returns: true 如果在 /System/ 或只读挂载点上
    public static func isSystemReadOnlyApp(_ app: UninstallEngine.InstalledApp) -> Bool {
        // 检查系统路径前缀
        let systemPaths = ["/System/", "/System/Applications/"]
        for prefix in systemPaths {
            if app.path.hasPrefix(prefix) { return true }
        }
        
        // 检查是否在只读挂载点（处理 firmlink 场景）
        var statInfo = statfs()
        if statfs(app.path, &statInfo) == 0 {
            let flags = UInt32(statInfo.f_flags)
            if (flags & UInt32(MNT_RDONLY)) != 0 { return true }
        }
        
        return false
    }
    
    /// 验证单个路径
    public static func validate(path: String) throws -> String {
        let fileManager = FileManager.default
        
        // 1. 检查路径是否存在
        guard fileManager.fileExists(atPath: path) else {
            throw PathValidationError.pathNotExists(path)
        }
        
        // 2. 标准化路径
        let standardizedPath = (path as NSString).standardizingPath
        
        // 3. 解析符号链接获取真实路径
        let resolvedPath: String
        do {
            resolvedPath = try fileManager.destinationOfSymbolicLink(atPath: standardizedPath)
        } catch {
            // 不是符号链接，使用标准化路径
            resolvedPath = standardizedPath
        }
        
        let pathToCheck = (resolvedPath as NSString).standardizingPath
        
        // 4. 检查是否在阻止列表中
        for blocked in blockedPrefixes {
            if pathToCheck.hasPrefix(blocked) {
                throw PathValidationError.systemPathBlocked(path)
            }
        }
        
        // 5. 检查是否在白名单中
        var isAllowed = false
        for allowed in allowedPrefixes {
            if pathToCheck.hasPrefix(allowed) {
                isAllowed = true
                break
            }
        }
        
        guard isAllowed else {
            throw PathValidationError.pathNotAllowed(path)
        }
        
        // 6. 确保解析后的路径仍在白名单内（防止符号链接逃逸）
        if pathToCheck != standardizedPath {
            var resolvedAllowed = false
            for allowed in allowedPrefixes {
                if pathToCheck.hasPrefix(allowed) {
                    resolvedAllowed = true
                    break
                }
            }
            
            // 也检查阻止列表
            for blocked in blockedPrefixes {
                if pathToCheck.hasPrefix(blocked) {
                    throw PathValidationError.symlinkEscape(original: path, resolved: pathToCheck)
                }
            }
            
            guard resolvedAllowed else {
                throw PathValidationError.symlinkEscape(original: path, resolved: pathToCheck)
            }
        }
        
        return pathToCheck
    }
    
    /// 验证应用是否可以被删除
    /// - Note: 不再根据 Bundle ID 阻止 Apple App，改用路径判定
    ///         Apple App (com.apple.*) 在 /Applications/ 下可以删除，但需 UI 层确认
    public static func validateApp(_ app: UninstallEngine.InstalledApp) throws {
        // 系统只读卷上的 App 永远禁止删除
        if isSystemReadOnlyApp(app) {
            throw PathValidationError.systemPathBlocked(app.path)
        }
        
        // 检查路径是否在白名单中
        _ = try validate(path: app.path)
    }

}

// MARK: - UninstallEngine Extension

extension UninstallEngine {
    
    /// 创建删除计划（异步计算体积）
    public func createDeletionPlan(for app: InstalledApp) async throws -> DeletionPlan {
        logger.info("Creating deletion plan for: \(app.name)")
        
        // 验证应用可删除
        try PathValidator.validateApp(app)
        
        var items: [DeletionItem] = []
        
        // 添加残留文件（计算体积用于显示）
        let residuals = try findResidualFiles(for: app, calculateSizes: true)
        for residual in residuals {
            do {
                let resolvedPath = try PathValidator.validate(path: residual.path)
                let item = DeletionItem(
                    path: residual.path,
                    resolvedPath: resolvedPath,
                    kind: DeletionItemKind(from: residual.type),
                    size: residual.size
                )
                items.append(item)
            } catch {
                logger.warning("Skipping invalid residual path: \(residual.path) - \(error)")
            }
        }
        
        // 添加应用本体（放在最后删除）
        // 计算应用体积（如果还没计算）
        var appSize = app.size
        if appSize == 0 {
            appSize = await calculateSizeAsync(at: app.path)
        }
        
        let appResolvedPath = try PathValidator.validate(path: app.path)
        let appItem = DeletionItem(
            path: app.path,
            resolvedPath: appResolvedPath,
            kind: .app,
            size: appSize
        )
        items.append(appItem)
        
        logger.info("Deletion plan created with \(items.count) items")
        return DeletionPlan(app: app, items: items)
    }
    
    #if !SWIFTSWEEP_MAS
    /// 执行删除计划 (仅 Developer ID 版本)
    /// - Parameters:
    ///   - plan: 删除计划
    ///   - permanentDelete: true 永久删除，false 移到废纸篓（默认）
    @available(macOS 13.0, *)
    public func executeDeletionPlan(_ plan: DeletionPlan, permanentDelete: Bool = false) async throws -> DeletionResult {
        logger.info("Executing deletion plan for: \(plan.app.name), permanent: \(permanentDelete)")
        
        var results: [DeletionItemResult] = []
        let fm = FileManager.default
        
        // 按顺序删除（残留文件先删，应用最后删）
        for item in plan.items {
            do {
                // 再次在执行前验证路径（双重保险）
                _ = try PathValidator.validate(path: item.path)
                
                let url = URL(fileURLWithPath: item.path)
                
                // 策略：先尝试标准删除，权限不足时再调用 Helper
                var deletedWithStandard = false
                
                do {
                    if permanentDelete {
                        // 永久删除
                        try fm.removeItem(at: url)
                    } else {
                        // 移到废纸篓（推荐，用户可恢复）
                        try fm.trashItem(at: url, resultingItemURL: nil)
                    }
                    deletedWithStandard = true
                } catch let error as NSError {
                    // 检查是否为权限错误
                    let isPermissionError = error.domain == NSCocoaErrorDomain && 
                        (error.code == NSFileWriteNoPermissionError || 
                         error.code == NSFileReadNoPermissionError ||
                         error.code == CocoaError.fileWriteNoPermission.rawValue)
                    
                    let isPosixPermError = error.domain == NSPOSIXErrorDomain &&
                        (error.code == Int(EPERM) || error.code == Int(EACCES))
                    
                    if isPermissionError || isPosixPermError {
                        // 权限不足，使用 Helper 提权删除
                        logger.info("Permission denied for \(item.path), falling back to Helper")
                        let helper = HelperClient.shared
                        if helper.checkStatus() == .enabled {
                            try await helper.deleteFile(at: item.path)
                            deletedWithStandard = true
                        } else {
                            throw error // Helper 未安装，抛出原始错误
                        }
                    } else {
                        throw error // 其他错误直接抛出
                    }
                }
                
                if deletedWithStandard {
                    results.append(DeletionItemResult(item: item, success: true))
                    logger.info("Deleted: \(item.path)")
                }
            } catch {
                logger.error("Failed to delete: \(item.path) - \(error)")
                results.append(DeletionItemResult(item: item, success: false, error: error.localizedDescription))
            }
        }
        
        let result = DeletionResult(itemResults: results)
        logger.info("Deletion complete: \(result.successCount) success, \(result.failureCount) failed")
        
        return result
    }
    
    /// 重试删除失败的项目
    @available(macOS 13.0, *)
    public func retryFailedDeletions(_ failedItems: [DeletionItem]) async throws -> DeletionResult {
        logger.info("Retrying \(failedItems.count) failed deletions")
        
        let helper = HelperClient.shared
        guard helper.checkStatus() == .enabled else {
            throw HelperClient.HelperError.notInstalled
        }
        
        var results: [DeletionItemResult] = []
        
        for item in failedItems {
            do {
                _ = try PathValidator.validate(path: item.path)
                try await helper.deleteFile(at: item.path)
                results.append(DeletionItemResult(item: item, success: true))
            } catch {
                results.append(DeletionItemResult(item: item, success: false, error: error.localizedDescription))
            }
        }
        
        return DeletionResult(itemResults: results)
    }
    #endif
}
