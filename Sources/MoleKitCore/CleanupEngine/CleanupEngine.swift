import Foundation
import Logging

/// MoleKit 清理引擎 - 负责文件清理、扫描、和删除操作
public final class CleanupEngine {
    public static let shared = CleanupEngine()
    
    private let logger = Logger(label: "com.molekit.cleanup")
    
    public struct CleanupItem: Identifiable {
        public let id: UUID
        public let name: String
        public let path: String
        public let size: Int64
        public let itemCount: Int
        public let category: CleanupCategory
        public var isSelected: Bool = true
        
        public init(name: String, path: String, size: Int64, itemCount: Int, category: CleanupCategory) {
            self.id = UUID()
            self.name = name
            self.path = path
            self.size = size
            self.itemCount = itemCount
            self.category = category
        }
    }
    
    public enum CleanupCategory: String, Codable {
        case userCache = "User Cache"
        case systemCache = "System Cache"
        case logs = "Logs"
        case trash = "Trash"
        case browserCache = "Browser Cache"
        case developerTools = "Developer Tools"
        case applications = "Applications"
        case other = "Other"
    }
    
    private init() {}
    
    /// 扫描可清理的项目
    public func scanForCleanableItems() async throws -> [CleanupItem] {
        logger.info("Starting cleanup scan...")
        
        var items: [CleanupItem] = []
        
        // 扫描用户缓存
        items.append(contentsOf: try scanUserCache())
        
        // 扫描浏览器缓存
        items.append(contentsOf: try scanBrowserCache())
        
        // 扫描系统缓存
        items.append(contentsOf: try scanSystemCache())
        
        // 扫描日志
        items.append(contentsOf: try scanLogs())
        
        logger.info("Scan complete. Found \(items.count) cleanable items")
        return items
    }
    
    /// 执行清理操作
    public func performCleanup(items: [CleanupItem], dryRun: Bool = false) async throws -> Int64 {
        logger.info("Starting cleanup. Dry run: \(dryRun)")
        
        var freedBytes: Int64 = 0
        let fileManager = FileManager.default
        
        for item in items where item.isSelected {
            do {
                if dryRun {
                    logger.debug("Would delete: \(item.path)")
                    freedBytes += item.size
                } else {
                    try fileManager.removeItem(atPath: item.path)
                    freedBytes += item.size
                    logger.debug("Deleted: \(item.path)")
                }
            } catch {
                logger.error("Failed to delete \(item.path): \(error)")
            }
        }
        
        logger.info("Cleanup complete. Freed \(freedBytes) bytes")
        return freedBytes
    }
    
    // MARK: - Private Scanning Methods
    
    private func scanUserCache() throws -> [CleanupItem] {
        var items: [CleanupItem] = []
        let fileManager = FileManager.default
        
        // 1. User Caches (~/Library/Caches)
        if let cachesPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first {
            let cacheItems = try scanDirectory(at: cachesPath, category: .userCache)
            items.append(contentsOf: cacheItems)
        }
        
        // 2. User Logs (~/Library/Logs)
        if let logsPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first {
             let userLogs = logsPath + "/Logs"
             let logItems = try scanDirectory(at: userLogs, category: .logs)
             items.append(contentsOf: logItems)
        }
        
        // 3. User Trash (~/.Trash)
        let trashPath = NSHomeDirectory() + "/.Trash"
        if fileManager.fileExists(atPath: trashPath) {
             let trashItems = try scanDirectory(at: trashPath, category: .trash)
             items.append(contentsOf: trashItems)
        }
        
        return items
    }
    
    private func scanDirectory(at path: String, category: CleanupCategory) throws -> [CleanupItem] {
        let fileManager = FileManager.default
        var items: [CleanupItem] = []
        
        guard let subpaths = try? fileManager.contentsOfDirectory(atPath: path) else {
            return []
        }
        
        for subpath in subpaths {
            // Skip hidden files or system files if needed
            if subpath.hasPrefix(".") && subpath != ".Trash" { continue }
            
            let fullPath = path + "/" + subpath
            guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath) else { continue }
            
            let size = attrs[.size] as? Int64 ?? 0
            
            // For directories, we might want to calculate recursive size, but for now let's just list top-level
            // Real implementation should probably recursively calculate directory size
            var totalSize = size
            var count = 1
            
            if let type = attrs[.type] as? FileAttributeType, type == .typeDirectory {
                totalSize = calculateDirectorySize(at: fullPath)
                count = (try? fileManager.subpathsOfDirectory(atPath: fullPath))?.count ?? 0
            }
            
            // Only list items > 1KB to reduce noise
            if totalSize > 1024 {
                let item = CleanupItem(
                    name: subpath,
                    path: fullPath,
                    size: totalSize,
                    itemCount: count,
                    category: category
                )
                items.append(item)
            }
        }
        
        return items
    }
    
    private func calculateDirectorySize(at path: String) -> Int64 {
        let fileManager = FileManager.default
        var size: Int64 = 0
        
        if let enumerator = fileManager.enumerator(atPath: path) {
            for case let file as String in enumerator {
                let filePath = path + "/" + file
                if let attrs = try? fileManager.attributesOfItem(atPath: filePath) {
                    size += attrs[.size] as? Int64 ?? 0
                }
            }
        }
        return size
    }
    
    private func scanBrowserCache() throws -> [CleanupItem] {
        var items: [CleanupItem] = []
        let fileManager = FileManager.default
        let home = NSHomeDirectory()
        
        // 1. Google Chrome
        let chromePath = home + "/Library/Caches/Google/Chrome"
        if fileManager.fileExists(atPath: chromePath) {
             items.append(contentsOf: try scanDirectory(at: chromePath, category: .browserCache))
        }
        
        // 2. Safari
        let safariPath = home + "/Library/Caches/com.apple.Safari"
        if fileManager.fileExists(atPath: safariPath) {
            // Safari cache is often a single directory or specific files
            let item = CleanupItem(
                name: "Safari Cache",
                path: safariPath,
                size: calculateDirectorySize(at: safariPath),
                itemCount: (try? fileManager.subpathsOfDirectory(atPath: safariPath))?.count ?? 0,
                category: .browserCache
            )
            items.append(item)
        }
        
        // 3. Firefox
        let firefoxPath = home + "/Library/Caches/Firefox"
        if fileManager.fileExists(atPath: firefoxPath) {
            items.append(contentsOf: try scanDirectory(at: firefoxPath, category: .browserCache))
        }
        
        return items
    }
    
    private func scanSystemCache() throws -> [CleanupItem] {
        var items: [CleanupItem] = []
        let fileManager = FileManager.default
        
        // Scan ~/Library/Caches for com.apple.*
        if let cachesPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first {
            guard let subpaths = try? fileManager.contentsOfDirectory(atPath: cachesPath) else { return [] }
            
            for subpath in subpaths {
                if subpath.starts(with: "com.apple.") {
                    let fullPath = cachesPath + "/" + subpath
                    let size = calculateDirectorySize(at: fullPath)
                    
                    if size > 1024 * 1024 { // Only show system caches > 1MB
                        let item = CleanupItem(
                            name: subpath,
                            path: fullPath,
                            size: size,
                            itemCount: (try? fileManager.subpathsOfDirectory(atPath: fullPath))?.count ?? 0,
                            category: .systemCache
                        )
                        items.append(item)
                    }
                }
            }
        }
        
        return items
    }
    
    private func scanLogs() throws -> [CleanupItem] {
        var items: [CleanupItem] = []
        
        // Setup standard log paths
        let logPaths = [
            NSHomeDirectory() + "/Library/Logs",
            "/Library/Logs" // System logs (might require recursion/permissions, but good to list)
        ]
        
        for path in logPaths {
            items.append(contentsOf: try scanDirectory(at: path, category: .logs))
        }
        
        return items
    }
}
