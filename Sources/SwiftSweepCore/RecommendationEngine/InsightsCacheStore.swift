import Foundation

/// Caches Insights context data to avoid repeated scans
public actor InsightsCacheStore {
  public static let shared = InsightsCacheStore()

  // MARK: - Cache DTOs (Codable)

  public struct CachedContext: Codable {
    public let timestamp: Date
    public let downloadsFiles: [CachedFileInfo]
    public let cleanupItems: [CachedCleanupItem]
    public let installedApps: [CachedAppInfo]?
  }

  public struct CachedFileInfo: Codable {
    public let path: String
    public let name: String
    public let sizeBytes: Int64
    public let creationDate: Date?
    public let lastAccessDate: Date?
    public let contentModificationDate: Date?
    public let isDirectory: Bool

    public init(from fileInfo: FileInfo) {
      self.path = fileInfo.path
      self.name = fileInfo.name
      self.sizeBytes = fileInfo.sizeBytes
      self.creationDate = fileInfo.creationDate
      self.lastAccessDate = fileInfo.lastAccessDate
      self.contentModificationDate = fileInfo.contentModificationDate
      self.isDirectory = fileInfo.isDirectory
    }

    public func toFileInfo() -> FileInfo {
      FileInfo(
        path: path,
        name: name,
        sizeBytes: sizeBytes,
        creationDate: creationDate,
        lastAccessDate: lastAccessDate,
        contentModificationDate: contentModificationDate,
        isDirectory: isDirectory
      )
    }
  }

  public struct CachedCleanupItem: Codable {
    public let path: String
    public let sizeBytes: Int64
    public let category: String

    public init(from item: CleanupItem) {
      self.path = item.path
      self.sizeBytes = item.sizeBytes
      self.category = item.category
    }

    public func toCleanupItem() -> CleanupItem {
      CleanupItem(path: path, sizeBytes: sizeBytes, category: category)
    }
  }

  public struct CachedAppInfo: Codable {
    public let bundleID: String
    public let name: String
    public let path: String
    public let sizeBytes: Int64?
    public let lastUsedDate: Date?

    public init(from appInfo: AppInfo) {
      self.bundleID = appInfo.bundleID
      self.name = appInfo.name
      self.path = appInfo.path
      self.sizeBytes = appInfo.sizeBytes
      self.lastUsedDate = appInfo.lastUsedDate
    }

    public func toAppInfo() -> AppInfo {
      AppInfo(
        bundleID: bundleID,
        name: name,
        path: path,
        sizeBytes: sizeBytes,
        lastUsedDate: lastUsedDate
      )
    }
  }

  /// Result of cache lookup
  public struct CacheResult {
    public let isCacheHit: Bool
    public let cacheAge: TimeInterval?
    public let downloadsFiles: [FileInfo]
    public let cleanupItems: [CleanupItem]
    public let installedApps: [AppInfo]?
  }

  // MARK: - Configuration

  private let ttl: TimeInterval = 300  // 5 minutes
  private var cachedContext: CachedContext?

  private var cacheFileURL: URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let dir = appSupport.appendingPathComponent("SwiftSweep", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("insights_cache.json")
  }

  private init() {
    loadFromDisk()
  }

  // MARK: - Public API

  /// Get cached data if available and not expired
  public func getCached() -> CacheResult? {
    guard let cached = cachedContext else { return nil }

    let age = Date().timeIntervalSince(cached.timestamp)
    guard age < ttl else {
      // Expired
      return nil
    }

    return CacheResult(
      isCacheHit: true,
      cacheAge: age,
      downloadsFiles: cached.downloadsFiles.map { $0.toFileInfo() },
      cleanupItems: cached.cleanupItems.map { $0.toCleanupItem() },
      installedApps: cached.installedApps?.map { $0.toAppInfo() }
    )
  }

  /// Cache new data
  public func cache(
    downloadsFiles: [FileInfo],
    cleanupItems: [CleanupItem],
    installedApps: [AppInfo]?
  ) {
    let context = CachedContext(
      timestamp: Date(),
      downloadsFiles: downloadsFiles.map { CachedFileInfo(from: $0) },
      cleanupItems: cleanupItems.map { CachedCleanupItem(from: $0) },
      installedApps: installedApps?.map { CachedAppInfo(from: $0) }
    )

    self.cachedContext = context
    saveToDisk(context)
  }

  /// Invalidate cache
  public func invalidate() {
    cachedContext = nil
    try? FileManager.default.removeItem(at: cacheFileURL)
  }

  /// Check if cache is expired
  public func isExpired() -> Bool {
    guard let cached = cachedContext else { return true }
    return Date().timeIntervalSince(cached.timestamp) >= ttl
  }

  // MARK: - Persistence

  private func loadFromDisk() {
    guard FileManager.default.fileExists(atPath: cacheFileURL.path),
      let data = try? Data(contentsOf: cacheFileURL),
      let cached = try? JSONDecoder().decode(CachedContext.self, from: data)
    else {
      return
    }

    // Check if still valid
    if Date().timeIntervalSince(cached.timestamp) < ttl {
      cachedContext = cached
    }
  }

  private func saveToDisk(_ context: CachedContext) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    guard let data = try? encoder.encode(context) else { return }
    try? data.write(to: cacheFileURL, options: .atomic)
  }
}
