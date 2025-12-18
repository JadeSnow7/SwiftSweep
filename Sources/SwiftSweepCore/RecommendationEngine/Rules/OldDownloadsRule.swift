import Foundation

// MARK: - OldDownloadsRule

/// Generates recommendations for old files in ~/Downloads.
public struct OldDownloadsRule: RecommendationRule {
  public let id = "old_downloads"
  public let displayName = "Old Downloads Cleanup"
  public let capabilities: [RuleCapability] = [.downloadsAccess]

  /// Files older than this many days are considered "old"
  private let ageDaysThreshold: Int = 30
  /// Minimum total size to generate a recommendation (bytes)
  private let minTotalSizeBytes: Int64 = 50_000_000  // 50 MB
  /// Files larger than this are highlighted individually
  private let largeFileThreshold: Int64 = 200_000_000  // 200 MB

  public init() {}

  public func evaluate(context: RecommendationContext) async throws -> [Recommendation] {
    guard let files = context.downloadsFiles, !files.isEmpty else { return [] }

    let cutoffDate =
      Calendar.current.date(byAdding: .day, value: -ageDaysThreshold, to: context.currentDate)
      ?? context.currentDate

    // Find old files
    var oldFiles: [FileInfo] = []
    var totalSize: Int64 = 0
    var largeFiles: [FileInfo] = []

    for file in files {
      // Use creation date, falling back to modification date
      let fileDate = file.creationDate ?? file.contentModificationDate

      guard let date = fileDate, date < cutoffDate else { continue }

      oldFiles.append(file)
      totalSize += file.sizeBytes

      if file.sizeBytes >= largeFileThreshold {
        largeFiles.append(file)
      }
    }

    // Only generate recommendation if total size exceeds threshold
    guard totalSize >= minTotalSizeBytes else { return [] }

    // Build evidence
    var evidence: [Evidence] = [
      Evidence(kind: .aggregate, label: "Old Files Count", value: "\(oldFiles.count) files"),
      Evidence(kind: .aggregate, label: "Total Size", value: formatBytes(totalSize)),
      Evidence(kind: .metadata, label: "Age Threshold", value: "\(ageDaysThreshold) days"),
    ]

    // Add large files as individual evidence
    for largeFile in largeFiles.prefix(5) {
      evidence.append(
        Evidence(
          kind: .path,
          label: largeFile.name,
          value: formatBytes(largeFile.sizeBytes)
        ))
    }

    // Build actions
    let paths = oldFiles.map { $0.path }
    let actions: [Action] = [
      Action(
        type: .cleanupTrash, payload: .paths(paths), requiresConfirmation: true,
        supportsDryRun: true),
      Action(
        type: .openFinder,
        payload: .paths([
          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        ]), requiresConfirmation: false, supportsDryRun: false),
    ]

    return [
      Recommendation(
        id: id,
        title: "Old Files in Downloads",
        summary:
          "\(oldFiles.count) files older than \(ageDaysThreshold) days, totaling \(formatBytes(totalSize)).",
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
