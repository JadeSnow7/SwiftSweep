import Foundation

// MARK: - BrowserCacheRule

/// Detects large browser caches (Safari, Chrome, Firefox, Edge).
public struct BrowserCacheRule: RecommendationRule {
  public let id = "browser_cache"
  public let displayName = "Browser Cache"
  public let capabilities: [RuleCapability] = [.cleanupItems]

  /// Minimum total size to trigger recommendation
  private let minTotalSize: Int64 = 200_000_000  // 200 MB

  /// Browser cache paths (relative to home directory)
  private let browserPaths: [(name: String, path: String)] = [
    ("Safari", "Library/Caches/com.apple.Safari"),
    ("Safari Previews", "Library/Caches/com.apple.Safari.SafeBrowsing"),
    ("Chrome", "Library/Caches/Google/Chrome"),
    ("Chrome Canary", "Library/Caches/Google/Chrome Canary"),
    ("Firefox", "Library/Caches/Firefox"),
    ("Edge", "Library/Caches/Microsoft Edge"),
    ("Brave", "Library/Caches/BraveSoftware/Brave-Browser"),
    ("Arc", "Library/Caches/company.thebrowser.Browser"),
    ("Opera", "Library/Caches/com.operasoftware.Opera"),
  ]

  public init() {}

  public func evaluate(context: RecommendationContext) async throws -> [Recommendation] {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser

    var foundCaches: [(name: String, path: String, size: Int64)] = []

    for (name, relativePath) in browserPaths {
      let fullPath = home.appendingPathComponent(relativePath)

      guard fm.fileExists(atPath: fullPath.path) else { continue }

      let size = calculateDirectorySize(at: fullPath)
      if size > 10_000_000 {  // Only include if > 10MB
        foundCaches.append((name, fullPath.path, size))
      }
    }

    let totalSize = foundCaches.reduce(0) { $0 + $1.size }

    guard totalSize >= minTotalSize, !foundCaches.isEmpty else { return [] }

    // Sort by size descending
    foundCaches.sort { $0.size > $1.size }

    // Build evidence
    var evidence: [Evidence] = [
      Evidence(kind: .aggregate, label: "Total Cache", value: formatBytes(totalSize)),
      Evidence(kind: .aggregate, label: "Browsers", value: "\(foundCaches.count) found"),
    ]

    for cache in foundCaches.prefix(5) {
      evidence.append(Evidence(kind: .path, label: cache.name, value: formatBytes(cache.size)))
    }

    // Build actions
    let paths = foundCaches.map { $0.path }
    let actions: [Action] = [
      Action(
        type: .cleanupTrash, payload: .paths(paths), requiresConfirmation: true,
        supportsDryRun: true)
    ]

    return [
      Recommendation(
        id: id,
        title: "Browser Caches",
        summary:
          "\(foundCaches.count) browser caches totaling \(formatBytes(totalSize)). Safe to clear.",
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

  private func calculateDirectorySize(at url: URL) -> Int64 {
    let fm = FileManager.default
    var size: Int64 = 0

    guard
      let enumerator = fm.enumerator(
        at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
    else {
      return 0
    }

    for case let fileURL as URL in enumerator {
      if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
        let fileSize = resourceValues.fileSize
      {
        size += Int64(fileSize)
      }
    }

    return size
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1 {
      return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_000_000
    return String(format: "%.0f MB", mb)
  }
}
