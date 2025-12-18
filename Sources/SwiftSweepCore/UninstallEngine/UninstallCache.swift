import Foundation
import GRDB
import Logging

// MARK: - Cached Models

/// Cached app metadata stored in SQLite
public struct CachedApp: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "apps"
    
    public var path: String  // Primary key
    public var bundleID: String
    public var name: String
    public var version: String?
    public var mtime: Date
    public var sizeBytes: Int64
    public var lastUsed: Date?
    public var scannedAt: Date
    
    public init(from app: UninstallEngine.InstalledApp) {
        self.path = app.path
        self.bundleID = app.bundleID
        self.name = app.name
        self.version = nil  // TODO: Extract from Info.plist
        self.mtime = app.lastUsed ?? Date()
        self.sizeBytes = app.size
        self.lastUsed = app.lastUsed
        self.scannedAt = Date()
    }
    
    public func toInstalledApp() -> UninstallEngine.InstalledApp {
        UninstallEngine.InstalledApp(
            name: name,
            bundleID: bundleID,
            path: path,
            size: sizeBytes,
            lastUsed: lastUsed
        )
    }
}

/// Cached residual file metadata
public struct CachedResidual: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "residuals"
    
    public var id: Int64?
    public var appPath: String
    public var path: String
    public var type: String
    public var sizeBytes: Int64
    public var scannedAt: Date
    
    public init(from residual: UninstallEngine.ResidualFile, appPath: String) {
        self.id = nil
        self.appPath = appPath
        self.path = residual.path
        self.type = residual.type.rawValue
        self.sizeBytes = residual.size
        self.scannedAt = Date()
    }
    
    public func toResidualFile() -> UninstallEngine.ResidualFile {
        let residualType = UninstallEngine.ResidualType(rawValue: type) ?? .other
        return UninstallEngine.ResidualFile(path: path, size: sizeBytes, type: residualType)
    }
}

// MARK: - UninstallCache

/// SQLite-based cache for uninstall data
public actor UninstallCache {
    public static let shared = UninstallCache()
    
    private var dbQueue: DatabaseQueue?
    private let logger = Logger(label: "com.swiftsweep.uninstall-cache")
    
    /// Database file path
    private var databaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let swiftSweepDir = appSupport.appendingPathComponent("SwiftSweep", isDirectory: true)
        return swiftSweepDir.appendingPathComponent("uninstall_cache.sqlite")
    }
    
    private init() {
        Task {
            await setupDatabase()
        }
    }
    
    // MARK: - Setup
    
    private func setupDatabase() {
        do {
            // Ensure directory exists
            let dir = databaseURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            
            // Open database
            dbQueue = try DatabaseQueue(path: databaseURL.path)
            
            // Create tables
            try dbQueue?.write { db in
                // Apps table
                try db.create(table: "apps", ifNotExists: true) { t in
                    t.column("path", .text).primaryKey()
                    t.column("bundleID", .text).notNull().indexed()
                    t.column("name", .text).notNull()
                    t.column("version", .text)
                    t.column("mtime", .datetime).notNull()
                    t.column("sizeBytes", .integer).notNull()
                    t.column("lastUsed", .datetime)
                    t.column("scannedAt", .datetime).notNull()
                }
                
                // Residuals table
                try db.create(table: "residuals", ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("appPath", .text).notNull().indexed()
                        .references("apps", column: "path", onDelete: .cascade)
                    t.column("path", .text).notNull()
                    t.column("type", .text).notNull()
                    t.column("sizeBytes", .integer).notNull()
                    t.column("scannedAt", .datetime).notNull()
                }
            }
            
            logger.info("UninstallCache database initialized at \(databaseURL.path)")
        } catch {
            logger.error("Failed to setup UninstallCache database: \(error)")
        }
    }
    
    // MARK: - Apps CRUD
    
    /// Load all cached apps (fast, typically < 50ms)
    public func loadCachedApps() -> [CachedApp] {
        guard let dbQueue = dbQueue else { return [] }
        
        do {
            return try dbQueue.read { db in
                try CachedApp.order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
            }
        } catch {
            logger.error("Failed to load cached apps: \(error)")
            return []
        }
    }
    
    /// Get a single cached app by path
    public func getCachedApp(path: String) -> CachedApp? {
        guard let dbQueue = dbQueue else { return nil }
        
        do {
            return try dbQueue.read { db in
                try CachedApp.fetchOne(db, key: path)
            }
        } catch {
            logger.error("Failed to get cached app: \(error)")
            return nil
        }
    }
    
    /// Save or update an app
    public func saveApp(_ app: UninstallEngine.InstalledApp) {
        guard let dbQueue = dbQueue else { return }
        
        let cached = CachedApp(from: app)
        do {
            try dbQueue.write { db in
                try cached.save(db)
            }
        } catch {
            logger.error("Failed to save app: \(error)")
        }
    }
    
    /// Save multiple apps (batch insert)
    public func saveApps(_ apps: [UninstallEngine.InstalledApp]) {
        guard let dbQueue = dbQueue else { return }
        
        do {
            try dbQueue.write { db in
                for app in apps {
                    let cached = CachedApp(from: app)
                    try cached.save(db)
                }
            }
        } catch {
            logger.error("Failed to save apps: \(error)")
        }
    }
    
    // MARK: - Residuals CRUD
    
    /// Load cached residuals for an app
    public func loadResiduals(for appPath: String) -> [CachedResidual] {
        guard let dbQueue = dbQueue else { return [] }
        
        do {
            return try dbQueue.read { db in
                try CachedResidual
                    .filter(Column("appPath") == appPath)
                    .fetchAll(db)
            }
        } catch {
            logger.error("Failed to load residuals: \(error)")
            return []
        }
    }
    
    /// Save residuals for an app (replaces existing)
    public func saveResiduals(_ residuals: [UninstallEngine.ResidualFile], for appPath: String) {
        guard let dbQueue = dbQueue else { return }
        
        do {
            try dbQueue.write { db in
                // Delete existing residuals for this app
                try CachedResidual
                    .filter(Column("appPath") == appPath)
                    .deleteAll(db)
                
                // Insert new residuals
                for residual in residuals {
                    var cached = CachedResidual(from: residual, appPath: appPath)
                    try cached.insert(db)
                }
            }
        } catch {
            logger.error("Failed to save residuals: \(error)")
        }
    }
    
    // MARK: - Cache Validation
    
    /// Check if a cached app is stale (mtime or version changed)
    public func isStale(cached: CachedApp, currentMtime: Date?, currentVersion: String?) -> Bool {
        // If no mtime available, consider stale
        guard let mtime = currentMtime else { return true }
        
        // Check mtime difference (> 1 second = stale)
        if abs(cached.mtime.timeIntervalSince(mtime)) > 1.0 {
            return true
        }
        
        // Check version if available
        if let cachedVer = cached.version, let currentVer = currentVersion {
            if cachedVer != currentVer {
                return true
            }
        }
        
        return false
    }
    
    /// Check if residuals TTL has expired (default 24h)
    public func residualsExpired(scannedAt: Date, ttlHours: Int = 24) -> Bool {
        let ttl = TimeInterval(ttlHours * 3600)
        return Date().timeIntervalSince(scannedAt) > ttl
    }
    
    // MARK: - Cleanup
    
    /// Remove cached entries for apps that no longer exist on disk
    public func cleanup() {
        guard let dbQueue = dbQueue else { return }
        
        do {
            let apps = try dbQueue.read { db in
                try CachedApp.fetchAll(db)
            }
            
            let fm = FileManager.default
            var removedCount = 0
            
            try dbQueue.write { db in
                for app in apps {
                    if !fm.fileExists(atPath: app.path) {
                        try CachedApp.deleteOne(db, key: app.path)
                        removedCount += 1
                    }
                }
            }
            
            if removedCount > 0 {
                logger.info("Cleaned up \(removedCount) stale cache entries")
            }
        } catch {
            logger.error("Failed to cleanup cache: \(error)")
        }
    }
    
    /// Clear all cached data
    public func clearAll() {
        guard let dbQueue = dbQueue else { return }
        
        do {
            try dbQueue.write { db in
                try CachedResidual.deleteAll(db)
                try CachedApp.deleteAll(db)
            }
            logger.info("Cache cleared")
        } catch {
            logger.error("Failed to clear cache: \(error)")
        }
    }
}
