import Foundation

/// Protocol for deep scanning application sizes.
public protocol DeepScanning {
    func calculateSize(for app: AppItem) async throws -> Int64
    func scanAllApps(in directory: URL, progress: @escaping (Int, Int) -> Void) async throws -> [String: Int64]
}

/// Deep scanner for calculating accurate "on-disk" sizes of applications.
public actor DeepScanner: DeepScanning {
    
    private let cacheStore: CacheStore
    private var isCancelled = false
    
    public init(cacheStore: CacheStore) {
        self.cacheStore = cacheStore
    }
    
    public func cancel() {
        isCancelled = true
    }
    
    /// Calculate the accurate allocated size of a single app bundle.
    public func calculateSize(for app: AppItem) async throws -> Int64 {
        // Check cache first
        if let cached = cacheStore.getMetadata(for: app.id),
           let currentMTime = app.contentModifiedDate,
           cacheStore.isValid(cached: cached, currentVersion: app.version, currentMTime: currentMTime) {
            return cached.sizeBytes
        }
        
        // Calculate actual size
        let size = try await calculateAllocatedSize(at: app.url)
        
        // Cache the result
        if let modTime = app.contentModifiedDate {
            let metadata = CachedAppMetadata(
                sizeBytes: size,
                scannedAt: Date(),
                bundleVersion: app.version,
                bundleMTime: modTime
            )
            cacheStore.setMetadata(metadata, for: app.id)
        }
        
        return size
    }
    
    /// Scan all apps in a directory and calculate their sizes.
    /// - Parameters:
    ///   - directory: The directory to scan (should be /Applications).
    ///   - progress: Callback with (current, total) counts.
    /// - Returns: Dictionary of app IDs to sizes.
    public func scanAllApps(in directory: URL, progress: @escaping (Int, Int) -> Void) async throws -> [String: Int64] {
        isCancelled = false
        
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }
        
        let appBundles = contents.filter { $0.pathExtension == "app" }
        let total = appBundles.count
        var results: [String: Int64] = [:]
        
        for (index, appURL) in appBundles.enumerated() {
            if isCancelled { break }
            
            let bundle = Bundle(url: appURL)
            let bundleID = bundle?.bundleIdentifier ?? appURL.path
            let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
            let mtime = try? appURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            
            // Check cache
            if let cached = cacheStore.getMetadata(for: bundleID),
               let currentMTime = mtime,
               cacheStore.isValid(cached: cached, currentVersion: version, currentMTime: currentMTime) {
                results[bundleID] = cached.sizeBytes
            } else {
                do {
                    let size = try await calculateAllocatedSize(at: appURL)
                    results[bundleID] = size
                    
                    // Cache result
                    if let modTime = mtime {
                        let metadata = CachedAppMetadata(
                            sizeBytes: size,
                            scannedAt: Date(),
                            bundleVersion: version,
                            bundleMTime: modTime
                        )
                        cacheStore.setMetadata(metadata, for: bundleID)
                    }
                } catch {
                    // Skip apps that fail to scan
                    continue
                }
            }
            
            // Throttle progress updates (every ~200ms worth of work, or just per item for now)
            progress(index + 1, total)
        }
        
        return results
    }
    
    /// Scan provided apps and calculate their sizes (ensures ID consistency).
    /// - Parameters:
    ///   - apps: The AppItem array to scan.
    ///   - progress: Callback with (current, total) counts.
    /// - Returns: Dictionary of AppItem.id to sizes.
    public func scanApps(_ apps: [AppItem], progress: @escaping (Int, Int) -> Void) async throws -> [String: Int64] {
        isCancelled = false
        
        let total = apps.count
        var results: [String: Int64] = [:]
        var lastProgressUpdate = Date()
        
        for (index, app) in apps.enumerated() {
            if isCancelled { break }
            
            // Check cache first
            if let cached = cacheStore.getMetadata(for: app.id),
               cacheStore.isValid(cached: cached, currentVersion: app.version, currentMTime: app.contentModifiedDate) {
                results[app.id] = cached.sizeBytes
            } else {
                do {
                    let size = try await calculateAllocatedSize(at: app.url)
                    results[app.id] = size
                    
                    // Cache result
                    if let modTime = app.contentModifiedDate {
                        let metadata = CachedAppMetadata(
                            sizeBytes: size,
                            scannedAt: Date(),
                            bundleVersion: app.version,
                            bundleMTime: modTime
                        )
                        cacheStore.setMetadata(metadata, for: app.id)
                    }
                } catch {
                    // Skip apps that fail to scan
                    continue
                }
            }
            
            // Throttle progress updates to ~200ms
            let now = Date()
            if now.timeIntervalSince(lastProgressUpdate) > 0.2 || index == total - 1 {
                progress(index + 1, total)
                lastProgressUpdate = now
            }
        }
        
        return results
    }
    
    // MARK: - Private Helpers
    
    private func calculateAllocatedSize(at url: URL) async throws -> Int64 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var totalSize: Int64 = 0
                
                let fm = FileManager.default
                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles],
                    errorHandler: nil
                ) else {
                    continuation.resume(returning: 0)
                    return
                }
                
                for case let fileURL as URL in enumerator {
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: [
                        .totalFileAllocatedSizeKey,
                        .fileAllocatedSizeKey,
                        .fileSizeKey,
                        .isDirectoryKey
                    ]) else {
                        continue
                    }
                    
                    // Skip directories themselves
                    if resourceValues.isDirectory == true {
                        continue
                    }
                    
                    // Prefer totalFileAllocatedSize > fileAllocatedSize > fileSize
                    if let allocatedSize = resourceValues.totalFileAllocatedSize {
                        totalSize += Int64(allocatedSize)
                    } else if let allocatedSize = resourceValues.fileAllocatedSize {
                        totalSize += Int64(allocatedSize)
                    } else if let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
                
                continuation.resume(returning: totalSize)
            }
        }
    }
}
