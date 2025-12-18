import Foundation
import Logging

// MARK: - Cached Models

/// Cached app info for SWR pattern
public struct CachedAppInfo: Codable {
    public let path: String
    public let bundleID: String
    public let name: String
    public var sizeBytes: Int64?
    public let mtime: Date
    public let scannedAt: Date
    
    public init(from app: UninstallEngine.InstalledApp) {
        self.path = app.path
        self.bundleID = app.bundleID
        self.name = app.name
        self.sizeBytes = app.size
        self.mtime = app.lastUsed ?? Date()
        self.scannedAt = Date()
    }
    
    public func toInstalledApp() -> UninstallEngine.InstalledApp {
        UninstallEngine.InstalledApp(
            name: name,
            bundleID: bundleID,
            path: path,
            size: sizeBytes ?? 0,
            lastUsed: mtime
        )
    }
}

/// Cached residual info
public struct CachedResidualInfo: Codable {
    public let appPath: String
    public let path: String
    public let type: String
    public var sizeBytes: Int64?
    public let scannedAt: Date
    
    public init(from residual: UninstallEngine.ResidualFile, appPath: String) {
        self.appPath = appPath
        self.path = residual.path
        self.type = residual.type.rawValue
        self.sizeBytes = residual.size
        self.scannedAt = Date()
    }
    
    public func toResidualFile() -> UninstallEngine.ResidualFile {
        let residualType = UninstallEngine.ResidualType(rawValue: type) ?? .other
        return UninstallEngine.ResidualFile(path: path, size: sizeBytes ?? 0, type: residualType)
    }
}

// MARK: - UninstallCacheStore

/// JSON-based cache store for uninstall data (SWR pattern)
public class UninstallCacheStore {
    public static let shared = UninstallCacheStore()
    
    private let logger = Logger(label: "com.swiftsweep.uninstall-cache")
    private let queue = DispatchQueue(label: "com.swiftsweep.uninstall-cache", qos: .utility)
    
    /// Cache file path (Application Support)
    private var cacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let swiftSweepDir = appSupport.appendingPathComponent("SwiftSweep", isDirectory: true)
        return swiftSweepDir.appendingPathComponent("uninstall_cache.json")
    }
    
    /// Residuals cache file path
    private var residualsCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let swiftSweepDir = appSupport.appendingPathComponent("SwiftSweep", isDirectory: true)
        return swiftSweepDir.appendingPathComponent("residuals_cache.json")
    }
    
    private init() {
        // Ensure cache directory exists
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    // MARK: - Apps Cache
    
    /// Load cached apps (fast, for SWR initial display)
    public func loadCachedApps() -> [CachedAppInfo] {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return [] }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            let apps = try JSONDecoder().decode([CachedAppInfo].self, from: data)
            logger.debug("Loaded \(apps.count) cached apps")
            return apps
        } catch {
            logger.warning("Failed to load cache: \(error)")
            return []
        }
    }
    
    /// Save apps to cache
    public func saveApps(_ apps: [CachedAppInfo]) {
        queue.async { [self] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(apps)
                try data.write(to: cacheURL, options: .atomic)
                logger.debug("Saved \(apps.count) apps to cache")
            } catch {
                logger.warning("Failed to save cache: \(error)")
            }
        }
    }
    
    /// Check if cached app is stale (mtime changed)
    public func isStale(_ cached: CachedAppInfo, currentMtime: Date?) -> Bool {
        guard let mtime = currentMtime else { return true }
        // Stale if mtime differs by > 1 second
        return abs(cached.mtime.timeIntervalSince(mtime)) > 1.0
    }
    
    // MARK: - Residuals Cache
    
    /// Load cached residuals for an app
    public func loadResiduals(for appPath: String) -> [CachedResidualInfo] {
        guard FileManager.default.fileExists(atPath: residualsCacheURL.path) else { return [] }
        
        do {
            let data = try Data(contentsOf: residualsCacheURL)
            let allResiduals = try JSONDecoder().decode([CachedResidualInfo].self, from: data)
            return allResiduals.filter { $0.appPath == appPath }
        } catch {
            logger.warning("Failed to load residuals cache: \(error)")
            return []
        }
    }
    
    /// Save residuals to cache (replaces existing for this app)
    public func saveResiduals(_ residuals: [CachedResidualInfo], for appPath: String) {
        queue.async { [self] in
            do {
                var allResiduals: [CachedResidualInfo] = []
                
                // Load existing and filter out this app's residuals
                if FileManager.default.fileExists(atPath: residualsCacheURL.path) {
                    let data = try Data(contentsOf: residualsCacheURL)
                    allResiduals = try JSONDecoder().decode([CachedResidualInfo].self, from: data)
                    allResiduals.removeAll { $0.appPath == appPath }
                }
                
                // Add new residuals
                allResiduals.append(contentsOf: residuals)
                
                // Save
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(allResiduals)
                try data.write(to: residualsCacheURL, options: .atomic)
            } catch {
                logger.warning("Failed to save residuals cache: \(error)")
            }
        }
    }
    
    /// Check if residuals are expired (TTL)
    public func residualsExpired(scannedAt: Date, ttlHours: Int = 24) -> Bool {
        let ttl = TimeInterval(ttlHours * 3600)
        return Date().timeIntervalSince(scannedAt) > ttl
    }
    
    // MARK: - Cleanup
    
    /// Clean up cache entries for apps that no longer exist
    public func cleanup() {
        queue.async { [self] in
            var apps = loadCachedApps()
            let fm = FileManager.default
            
            let beforeCount = apps.count
            apps.removeAll { !fm.fileExists(atPath: $0.path) }
            
            if apps.count != beforeCount {
                saveApps(apps)
                logger.info("Cleaned up \(beforeCount - apps.count) stale cache entries")
            }
        }
    }
    
    /// Clear all cached data
    public func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        try? FileManager.default.removeItem(at: residualsCacheURL)
        logger.info("Cache cleared")
    }
}
