import Foundation

/// Protocol for caching Deep Scan results.
public protocol CacheStoring {
    func loadCache() -> [String: CachedAppMetadata]
    func saveCache(_ cache: [String: CachedAppMetadata])
    func getMetadata(for appID: String) -> CachedAppMetadata?
    func setMetadata(_ metadata: CachedAppMetadata, for appID: String)
    func isValid(cached: CachedAppMetadata, currentVersion: String?, currentMTime: Date) -> Bool
}

/// Default implementation using UserDefaults.
public final class CacheStore: CacheStoring {
    private let defaults: UserDefaults
    private let cacheKey = "appInventory.sizeCache"
    private var memoryCache: [String: CachedAppMetadata]?
    
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }
    
    public func loadCache() -> [String: CachedAppMetadata] {
        if let cached = memoryCache {
            return cached
        }
        guard let data = defaults.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: CachedAppMetadata].self, from: data) else {
            memoryCache = [:]
            return [:]
        }
        memoryCache = cache
        return cache
    }
    
    public func saveCache(_ cache: [String: CachedAppMetadata]) {
        memoryCache = cache
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: cacheKey)
    }
    
    public func getMetadata(for appID: String) -> CachedAppMetadata? {
        return loadCache()[appID]
    }
    
    public func setMetadata(_ metadata: CachedAppMetadata, for appID: String) {
        var cache = loadCache()
        cache[appID] = metadata
        saveCache(cache)
    }
    
    /// Checks if cached metadata is still valid based on version and modification time.
    public func isValid(cached: CachedAppMetadata, currentVersion: String?, currentMTime: Date) -> Bool {
        // Invalidate if mtime changed
        if abs(cached.bundleMTime.timeIntervalSince(currentMTime)) > 1.0 {
            return false
        }
        // Invalidate if version changed (and version is available)
        if let currentVer = currentVersion, let cachedVer = cached.bundleVersion {
            if currentVer != cachedVer {
                return false
            }
        }
        return true
    }
}
