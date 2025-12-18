import Foundation

// MARK: - RecommendationContext

/// Aggregated input data for recommendation rules.
/// Rules query this context to generate recommendations.
/// Properties are optional to support lazy/partial loading.
public struct RecommendationContext: Sendable {

  /// System metrics (CPU, memory, disk usage)
  public let systemMetrics: SystemMetrics?

  /// Cleanup items from CleanupEngine scan
  public let cleanupItems: [CleanupItem]?

  /// Files in Downloads directory with metadata
  public let downloadsFiles: [FileInfo]?

  /// Installed applications (requires SwiftSweepAppInventory)
  public let installedApps: [AppInfo]?

  /// Current date (for relative time calculations)
  public let currentDate: Date

  public init(
    systemMetrics: SystemMetrics? = nil,
    cleanupItems: [CleanupItem]? = nil,
    downloadsFiles: [FileInfo]? = nil,
    installedApps: [AppInfo]? = nil,
    currentDate: Date = Date()
  ) {
    self.systemMetrics = systemMetrics
    self.cleanupItems = cleanupItems
    self.downloadsFiles = downloadsFiles
    self.installedApps = installedApps
    self.currentDate = currentDate
  }
}

// MARK: - Supporting Types for Context

/// Simplified system metrics for context (mirrors SystemMonitor.SystemMetrics)
public struct SystemMetrics: Sendable {
  public let cpuUsage: Double
  public let memoryUsage: Double
  public let memoryUsedBytes: Int64
  public let memoryTotalBytes: Int64
  public let diskUsage: Double
  public let diskUsedBytes: Int64
  public let diskTotalBytes: Int64
  public let diskFreeBytes: Int64

  public init(
    cpuUsage: Double = 0,
    memoryUsage: Double = 0,
    memoryUsedBytes: Int64 = 0,
    memoryTotalBytes: Int64 = 0,
    diskUsage: Double = 0,
    diskUsedBytes: Int64 = 0,
    diskTotalBytes: Int64 = 0,
    diskFreeBytes: Int64 = 0
  ) {
    self.cpuUsage = cpuUsage
    self.memoryUsage = memoryUsage
    self.memoryUsedBytes = memoryUsedBytes
    self.memoryTotalBytes = memoryTotalBytes
    self.diskUsage = diskUsage
    self.diskUsedBytes = diskUsedBytes
    self.diskTotalBytes = diskTotalBytes
    self.diskFreeBytes = diskFreeBytes
  }
}

/// Simplified cleanup item for context
public struct CleanupItem: Sendable {
  public let path: String
  public let sizeBytes: Int64
  public let category: String

  public init(path: String, sizeBytes: Int64, category: String) {
    self.path = path
    self.sizeBytes = sizeBytes
    self.category = category
  }
}

/// File information for downloads/directory scanning
public struct FileInfo: Sendable {
  public let path: String
  public let name: String
  public let sizeBytes: Int64
  public let creationDate: Date?
  public let lastAccessDate: Date?
  public let contentModificationDate: Date?
  public let isDirectory: Bool

  public init(
    path: String,
    name: String,
    sizeBytes: Int64,
    creationDate: Date? = nil,
    lastAccessDate: Date? = nil,
    contentModificationDate: Date? = nil,
    isDirectory: Bool = false
  ) {
    self.path = path
    self.name = name
    self.sizeBytes = sizeBytes
    self.creationDate = creationDate
    self.lastAccessDate = lastAccessDate
    self.contentModificationDate = contentModificationDate
    self.isDirectory = isDirectory
  }
}

/// Application information for unused app detection
public struct AppInfo: Sendable {
  public let bundleID: String
  public let name: String
  public let path: String
  public let sizeBytes: Int64?
  public let lastUsedDate: Date?

  public init(
    bundleID: String,
    name: String,
    path: String,
    sizeBytes: Int64? = nil,
    lastUsedDate: Date? = nil
  ) {
    self.bundleID = bundleID
    self.name = name
    self.path = path
    self.sizeBytes = sizeBytes
    self.lastUsedDate = lastUsedDate
  }
}
