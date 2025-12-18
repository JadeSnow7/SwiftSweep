import Foundation

// MARK: - LowDiskSpaceRule

/// Generates recommendations when disk space is critically low.
public struct LowDiskSpaceRule: RecommendationRule {
  public let id = "low_disk_space"
  public let displayName = "Low Disk Space Alert"
  public let capabilities: [RuleCapability] = [.systemMetrics]

  /// Threshold for critical disk usage (percentage)
  private let criticalThreshold: Double = 0.90  // 90%
  /// Threshold for warning disk usage (percentage)
  private let warningThreshold: Double = 0.80  // 80%

  public init() {}

  public func evaluate(context: RecommendationContext) async throws -> [Recommendation] {
    guard let metrics = context.systemMetrics else { return [] }

    let diskUsage = metrics.diskUsage
    let freeBytes = metrics.diskFreeBytes

    // Format free space for display
    let freeGB = Double(freeBytes) / 1_000_000_000
    let freeFormatted = String(format: "%.1f GB", freeGB)

    if diskUsage >= criticalThreshold {
      return [
        Recommendation(
          id: "\(id)_critical",
          title: "Critical: Disk Space Almost Full",
          summary: "Only \(freeFormatted) free. Immediate action recommended.",
          severity: .critical,
          risk: .low,
          confidence: .high,
          estimatedReclaimBytes: nil,
          evidence: [
            Evidence(kind: .metric, label: "Disk Usage", value: "\(Int(diskUsage * 100))%"),
            Evidence(kind: .metric, label: "Free Space", value: freeFormatted),
          ],
          actions: [
            Action(
              type: .rescan, payload: .none, requiresConfirmation: false, supportsDryRun: false)
          ],
          requirements: []
        )
      ]
    } else if diskUsage >= warningThreshold {
      return [
        Recommendation(
          id: "\(id)_warning",
          title: "Disk Space Running Low",
          summary: "\(freeFormatted) free. Consider cleaning up.",
          severity: .warning,
          risk: .low,
          confidence: .high,
          evidence: [
            Evidence(kind: .metric, label: "Disk Usage", value: "\(Int(diskUsage * 100))%"),
            Evidence(kind: .metric, label: "Free Space", value: freeFormatted),
          ],
          actions: [
            Action(
              type: .rescan, payload: .none, requiresConfirmation: false, supportsDryRun: false)
          ],
          requirements: []
        )
      ]
    }

    return []
  }
}
