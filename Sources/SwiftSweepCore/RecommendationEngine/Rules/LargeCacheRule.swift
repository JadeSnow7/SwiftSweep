import Foundation

// MARK: - LargeCacheRule

/// Detects large system and application caches.
public struct LargeCacheRule: RecommendationRule {
  public let id = "large_caches"
  public let displayName = "Large Caches"
  public let capabilities: [RuleCapability] = [.cleanupItems]

  /// Threshold for individual cache folder to be considered "large" (bytes)
  private let largeCacheThreshold: Int64 = 200_000_000  // 200 MB
  /// Minimum total to generate recommendation
  private let minTotalSizeBytes: Int64 = 500_000_000  // 500 MB

  public init() {}

  public func evaluate(context: RecommendationContext) async throws -> [Recommendation] {
    guard let cleanupItems = context.cleanupItems, !cleanupItems.isEmpty else { return [] }

    // Filter for cache categories (must match CleanupCategory.rawValue)
    let cacheCategories = ["User Cache", "System Cache", "Browser Cache"]
    let cacheItems = cleanupItems.filter { item in
      cacheCategories.contains(item.category)
    }

    // Group by parent directory and sum sizes
    var cacheGroups: [String: Int64] = [:]
    for item in cacheItems {
      let parentDir = (item.path as NSString).deletingLastPathComponent
      let appName = (parentDir as NSString).lastPathComponent
      cacheGroups[appName, default: 0] += item.sizeBytes
    }

    // Filter for large caches
    let largeCaches = cacheGroups.filter { $0.value >= largeCacheThreshold }
      .sorted { $0.value > $1.value }

    let totalSize = largeCaches.reduce(0) { $0 + $1.value }

    guard totalSize >= minTotalSizeBytes else { return [] }

    // Build evidence
    var evidence: [Evidence] = [
      Evidence(kind: .aggregate, label: "Large Caches Found", value: "\(largeCaches.count)"),
      Evidence(kind: .aggregate, label: "Total Size", value: formatBytes(totalSize)),
    ]

    for (name, size) in largeCaches.prefix(5) {
      evidence.append(Evidence(kind: .metadata, label: name, value: formatBytes(size)))
    }

    // Build actions using the original paths
    let paths = cacheItems.filter { item in
      let parentDir = (item.path as NSString).deletingLastPathComponent
      let appName = (parentDir as NSString).lastPathComponent
      return largeCaches.map { $0.key }.contains(appName)
    }.map { $0.path }

    let actions: [Action] = [
      Action(
        type: .cleanupTrash, payload: .paths(paths), requiresConfirmation: true,
        supportsDryRun: true)
    ]

    return [
      Recommendation(
        id: id,
        title: "Large Application Caches",
        summary:
          "\(largeCaches.count) apps have caches over 200 MB, totaling \(formatBytes(totalSize)).",
        severity: .info,
        risk: .low,
        confidence: .high,
        estimatedReclaimBytes: totalSize,
        evidence: evidence,
        actions: actions,
        requirements: []
      )
    ]
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1 {
      return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_000_000
    return String(format: "%.1f MB", mb)
  }
}
