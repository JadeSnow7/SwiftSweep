import Foundation

// MARK: - MailAttachmentsRule

/// Detects old downloaded mail attachments.
public struct MailAttachmentsRule: RecommendationRule {
  public let id = "mail_attachments"
  public let displayName = "Mail Attachments"
  public let capabilities: [RuleCapability] = [.downloadsAccess]

  /// Days to consider attachment as "old"
  private let ageDaysThreshold: Int = 60
  /// Minimum total size to generate recommendation
  private let minTotalSize: Int64 = 100_000_000  // 100 MB

  /// Mail-related paths
  private let mailPaths = [
    "Library/Mail Downloads",
    "Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
  ]

  public init() {}

  public func evaluate(context: RecommendationContext) async throws -> [Recommendation] {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let cutoffDate =
      Calendar.current.date(byAdding: .day, value: -ageDaysThreshold, to: context.currentDate)
      ?? context.currentDate

    var allFiles: [FileInfo] = []

    for relativePath in mailPaths {
      let fullPath = home.appendingPathComponent(relativePath)

      guard fm.fileExists(atPath: fullPath.path) else { continue }

      do {
        let contents = try fm.contentsOfDirectory(
          at: fullPath,
          includingPropertiesForKeys: [
            .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey,
          ])

        for url in contents {
          let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey,
          ])

          // Skip directories
          if resourceValues.isDirectory == true { continue }

          let fileDate = resourceValues.creationDate ?? resourceValues.contentModificationDate
          let size = Int64(resourceValues.fileSize ?? 0)

          // Only include old files
          guard let date = fileDate, date < cutoffDate else { continue }

          allFiles.append(
            FileInfo(
              path: url.path,
              name: url.lastPathComponent,
              sizeBytes: size,
              creationDate: resourceValues.creationDate,
              contentModificationDate: resourceValues.contentModificationDate
            ))
        }
      } catch {
        continue
      }
    }

    let totalSize = allFiles.reduce(0) { $0 + $1.sizeBytes }

    guard totalSize >= minTotalSize, !allFiles.isEmpty else { return [] }

    // Sort by size descending
    let sorted = allFiles.sorted { $0.sizeBytes > $1.sizeBytes }

    // Build evidence
    var evidence: [Evidence] = [
      Evidence(kind: .aggregate, label: "Old Attachments", value: "\(sorted.count) files"),
      Evidence(kind: .aggregate, label: "Total Size", value: formatBytes(totalSize)),
      Evidence(kind: .metadata, label: "Age Threshold", value: "\(ageDaysThreshold) days"),
    ]

    for file in sorted.prefix(5) {
      evidence.append(Evidence(kind: .path, label: file.name, value: formatBytes(file.sizeBytes)))
    }

    // Build actions
    let paths = sorted.map { $0.path }
    let actions: [Action] = [
      Action(
        type: .cleanupTrash, payload: .paths(paths), requiresConfirmation: true,
        supportsDryRun: true),
      Action(
        type: .openFinder,
        payload: .paths([mailPaths.first.map { home.appendingPathComponent($0).path } ?? ""]),
        requiresConfirmation: false, supportsDryRun: false),
    ]

    return [
      Recommendation(
        id: id,
        title: "Old Mail Attachments",
        summary:
          "\(sorted.count) mail attachments older than \(ageDaysThreshold) days (\(formatBytes(totalSize))).",
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
    if mb >= 1 {
      return String(format: "%.0f MB", mb)
    }
    let kb = Double(bytes) / 1_000
    return String(format: "%.0f KB", kb)
  }
}
