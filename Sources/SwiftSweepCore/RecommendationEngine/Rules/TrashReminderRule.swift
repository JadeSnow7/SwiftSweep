import Foundation

// MARK: - TrashReminderRule

/// Reminds user to empty Trash if it's taking up significant space.
public struct TrashReminderRule: RecommendationRule {
  public let id = "trash_reminder"
  public let displayName = "Trash Reminder"
  public let capabilities: [RuleCapability] = [.systemMetrics]

  /// Minimum Trash size to trigger reminder
  private let minTrashSize: Int64 = 1_000_000_000  // 1 GB

  public init() {}

  public func evaluate(context: RecommendationContext) async throws -> [Recommendation] {
    let fm = FileManager.default
    let trashURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")

    guard fm.fileExists(atPath: trashURL.path) else { return [] }

    let trashSize = calculateDirectorySize(at: trashURL)

    guard trashSize >= minTrashSize else { return [] }

    // Count items in Trash
    let itemCount =
      (try? fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil).count) ?? 0

    // Build evidence
    let evidence: [Evidence] = [
      Evidence(kind: .aggregate, label: "Trash Size", value: formatBytes(trashSize)),
      Evidence(kind: .aggregate, label: "Items", value: "\(itemCount) items"),
      Evidence(kind: .path, label: "Location", value: trashURL.path),
    ]

    // Determine severity based on size
    let severity: Severity
    if trashSize >= 10_000_000_000 {  // 10 GB
      severity = .warning
    } else {
      severity = .info
    }

    // Actions - empty trash
    let actions: [Action] = [
      Action(type: .emptyTrash, payload: .none, requiresConfirmation: true, supportsDryRun: false),
      Action(
        type: .openFinder, payload: .paths([trashURL.path]), requiresConfirmation: false,
        supportsDryRun: false),
    ]

    return [
      Recommendation(
        id: id,
        title: "Empty Trash",
        summary:
          "Your Trash has \(itemCount) items totaling \(formatBytes(trashSize)). Empty to reclaim space.",
        severity: severity,
        risk: .medium,  // Emptying trash is permanent
        confidence: .high,
        estimatedReclaimBytes: trashSize,
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
        at: url, includingPropertiesForKeys: [.fileSizeKey], options: [])
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
