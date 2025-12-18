import Foundation
import Logging

// MARK: - RecommendationEngine

/// Orchestrates recommendation rule evaluation and result aggregation.
public final class RecommendationEngine: @unchecked Sendable {
  public static let shared = RecommendationEngine()

  private let logger = Logger(label: "com.swiftsweep.recommendation")
  private var rules: [any RecommendationRule] = []
  private let lock = NSLock()

  private init() {
    // Register default rules
    registerDefaultRules()
  }

  // MARK: - Rule Registration

  /// Registers a recommendation rule.
  public func register(rule: some RecommendationRule) {
    lock.lock()
    defer { lock.unlock() }

    // Avoid duplicate registration
    if !rules.contains(where: { $0.id == rule.id }) {
      rules.append(rule)
      logger.debug("Registered rule: \(rule.id)")
    }
  }

  /// Unregisters a rule by ID.
  public func unregister(ruleID: String) {
    lock.lock()
    defer { lock.unlock() }
    rules.removeAll { $0.id == ruleID }
  }

  /// Returns all registered rule IDs.
  public var registeredRuleIDs: [String] {
    lock.lock()
    defer { lock.unlock() }
    return rules.map { $0.id }
  }

  // MARK: - Evaluation

  /// Evaluates all registered rules and returns sorted recommendations.
  /// - Parameter context: The context containing data for rule evaluation.
  /// - Returns: Recommendations sorted by severity, then by reclaim bytes.
  public func evaluate(context: RecommendationContext) async throws -> [Recommendation] {
    let rulesToEvaluate: [any RecommendationRule]

    lock.lock()
    rulesToEvaluate = rules
    lock.unlock()

    logger.info("Evaluating \(rulesToEvaluate.count) rules...")

    var allRecommendations: [Recommendation] = []

    for rule in rulesToEvaluate {
      do {
        let recommendations = try await rule.evaluate(context: context)
        allRecommendations.append(contentsOf: recommendations)
        logger.debug("Rule '\(rule.id)' generated \(recommendations.count) recommendations")
      } catch {
        logger.error("Rule '\(rule.id)' failed: \(error.localizedDescription)")
        // Continue with other rules
      }
    }

    // Sort: critical first, then by reclaim bytes (descending)
    let sorted = allRecommendations.sorted { lhs, rhs in
      if lhs.severity.sortOrder != rhs.severity.sortOrder {
        return lhs.severity.sortOrder < rhs.severity.sortOrder
      }
      return (lhs.estimatedReclaimBytes ?? 0) > (rhs.estimatedReclaimBytes ?? 0)
    }

    logger.info("Generated \(sorted.count) total recommendations")
    return sorted
  }

  /// Convenience method: builds context from system and evaluates.
  public func evaluateWithSystemContext() async throws -> [Recommendation] {
    let context = try await buildDefaultContext()
    return try await evaluate(context: context)
  }

  // MARK: - Context Building

  /// Builds a default context by querying system state.
  public func buildDefaultContext() async throws -> RecommendationContext {
    // Get system metrics
    let monitor = SystemMonitor.shared
    let metrics = try await monitor.getMetrics()

    let systemMetrics = SystemMetrics(
      cpuUsage: metrics.cpuUsage,
      memoryUsage: metrics.memoryUsage,
      memoryUsedBytes: metrics.memoryUsed,
      memoryTotalBytes: metrics.memoryTotal,
      diskUsage: metrics.diskUsage,
      diskUsedBytes: metrics.diskUsed,
      diskTotalBytes: metrics.diskTotal,
      diskFreeBytes: metrics.diskTotal - metrics.diskUsed
    )

    // Get cleanup items
    let cleanupEngine = CleanupEngine.shared
    let items = try await cleanupEngine.scanForCleanableItems()
    let cleanupItems = items.map { item in
      SwiftSweepCore.CleanupItem(
        path: item.path,
        sizeBytes: item.size,
        category: item.category.rawValue
      )
    }

    // Scan Downloads directory
    let downloadsFiles = scanDownloadsDirectory()

    return RecommendationContext(
      systemMetrics: systemMetrics,
      cleanupItems: cleanupItems,
      downloadsFiles: downloadsFiles,
      installedApps: nil,  // TODO: Integrate with AppInventory
      currentDate: Date()
    )
  }

  // MARK: - Private Helpers

  private func registerDefaultRules() {
    // Register built-in rules
    register(rule: LowDiskSpaceRule())
    register(rule: OldDownloadsRule())
    register(rule: DeveloperCacheRule())
    register(rule: LargeCacheRule())
    register(rule: UnusedAppsRule())
    register(rule: ScreenshotCleanupRule())
  }

  private func scanDownloadsDirectory() -> [FileInfo] {
    let fm = FileManager.default
    let downloadsPath = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

    guard fm.fileExists(atPath: downloadsPath.path) else { return [] }

    var files: [FileInfo] = []

    do {
      let contents = try fm.contentsOfDirectory(
        at: downloadsPath,
        includingPropertiesForKeys: [
          .fileSizeKey, .creationDateKey, .contentAccessDateKey, .contentModificationDateKey,
          .isDirectoryKey,
        ])

      for url in contents {
        let resourceValues = try url.resourceValues(forKeys: [
          .fileSizeKey, .creationDateKey, .contentAccessDateKey, .contentModificationDateKey,
          .isDirectoryKey,
        ])

        let fileInfo = FileInfo(
          path: url.path,
          name: url.lastPathComponent,
          sizeBytes: Int64(resourceValues.fileSize ?? 0),
          creationDate: resourceValues.creationDate,
          lastAccessDate: resourceValues.contentAccessDate,
          contentModificationDate: resourceValues.contentModificationDate,
          isDirectory: resourceValues.isDirectory ?? false
        )
        files.append(fileInfo)
      }
    } catch {
      logger.warning("Failed to scan Downloads: \(error.localizedDescription)")
    }

    return files
  }
}
