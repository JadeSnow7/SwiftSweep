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
  /// - Parameters:
  ///   - context: The context containing data for rule evaluation.
  ///   - onProgress: Optional callback for progress updates (ruleName, current, total).
  /// - Returns: Recommendations sorted by severity, then by reclaim bytes.
  public func evaluate(
    context: RecommendationContext,
    onProgress: ((String, Int, Int) -> Void)? = nil
  ) async throws -> [Recommendation] {
    let rulesToEvaluate: [any RecommendationRule]

    lock.lock()
    // Filter out disabled rules
    let enabledRuleIDs = RuleSettings.shared.enabledRuleIDs
    rulesToEvaluate = rules.filter { enabledRuleIDs.contains($0.id) }
    lock.unlock()

    let totalRules = rulesToEvaluate.count
    logger.info("Evaluating \(totalRules) rules in parallel...")

    // Parallel execution with TaskGroup
    let allRecommendations = await withTaskGroup(
      of: (String, [Recommendation]).self,
      returning: [Recommendation].self
    ) { group in
      for (index, rule) in rulesToEvaluate.enumerated() {
        group.addTask {
          do {
            // Timeout: 30 seconds per rule
            let recommendations = try await withThrowingTaskGroup(of: [Recommendation].self) {
              timeoutGroup in
              timeoutGroup.addTask {
                try await rule.evaluate(context: context)
              }
              timeoutGroup.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)  // 30 seconds
                throw RuleError.timeout(ruleId: rule.id)
              }

              // Return first to complete (either result or timeout)
              if let result = try await timeoutGroup.next() {
                timeoutGroup.cancelAll()
                return result
              }
              return []
            }

            return (rule.id, recommendations)
          } catch let error as RuleError {
            self.logger.warning("Rule '\(rule.id)' timed out")
            return (rule.id, [])
          } catch {
            self.logger.error("Rule '\(rule.id)' failed: \(error.localizedDescription)")
            return (rule.id, [])
          }
        }
      }

      var results: [Recommendation] = []
      var completed = 0

      for await (ruleId, recommendations) in group {
        completed += 1
        results.append(contentsOf: recommendations)
        onProgress?(ruleId, completed, totalRules)
        self.logger.debug(
          "Rule '\(ruleId)' generated \(recommendations.count) recommendations (\(completed)/\(totalRules))"
        )
      }

      return results
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

  /// Rule evaluation error types
  enum RuleError: Error {
    case timeout(ruleId: String)
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
      CleanupItem(
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
    register(rule: BrowserCacheRule())
    register(rule: TrashReminderRule())
    register(rule: MailAttachmentsRule())
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
