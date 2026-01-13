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
    return try await PerformanceMonitor.shared.track("recommendation.evaluate") {
      try await self.evaluateInternal(context: context, onProgress: onProgress)
    }
  }

  /// Internal implementation of evaluate
  private func evaluateInternal(
    context: RecommendationContext,
    onProgress: ((String, Int, Int) -> Void)? = nil
  ) async throws -> [Recommendation] {
    // Get rules with sync access before async work
    let enabledRuleIDs = RuleSettings.shared.enabledRuleIDs
    let rulesToEvaluate: [any RecommendationRule] = rules.filter { enabledRuleIDs.contains($0.id) }

    let totalRules = rulesToEvaluate.count
    logger.info("Evaluating \(totalRules) rules in parallel...")

    // Parallel execution with TaskGroup
    let allRecommendations = await withTaskGroup(
      of: (String, [Recommendation]).self,
      returning: [Recommendation].self
    ) { group in
      for rule in rulesToEvaluate {
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
          } catch _ as RuleError {
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

  /// Evaluation result with cache metadata
  public struct EvaluationResult {
    public let recommendations: [Recommendation]
    public let isCacheHit: Bool
    public let cacheAge: TimeInterval?
  }

  /// Convenience method: builds context from system and evaluates (original signature for compatibility).
  public func evaluateWithSystemContext() async throws -> [Recommendation] {
    let result = try await evaluateWithSystemContext(forceRefresh: false, installedApps: nil)
    return result.recommendations
  }

  public func evaluateWithSystemContext(
    forceRefresh: Bool,
    installedApps: [AppInfo]? = nil,
    onPhase: ((String) -> Void)? = nil
  ) async throws -> EvaluationResult {
    var cacheAge: TimeInterval? = nil

    // Try cache first
    if !forceRefresh, let cached = await InsightsCacheStore.shared.getCached() {
      cacheAge = cached.cacheAge

      onPhase?("Loading from cache...")

      // Build context from cache with fresh currentDate
      let systemMetrics = try await getSystemMetrics()
      let context = RecommendationContext(
        systemMetrics: systemMetrics,
        cleanupItems: cached.cleanupItems,
        downloadsFiles: cached.downloadsFiles,
        installedApps: cached.installedApps ?? installedApps,
        currentDate: Date()  // Fresh time to avoid drift
      )

      let recommendations = try await evaluate(context: context)
      return EvaluationResult(
        recommendations: recommendations, isCacheHit: true, cacheAge: cacheAge)
    }

    // Full scan
    onPhase?("Scanning system metrics...")
    let systemMetrics = try await getSystemMetrics()

    onPhase?("Scanning cleanup items...")
    let cleanupEngine = CleanupEngine.shared
    let items = try await cleanupEngine.scanForCleanableItems()
    let cleanupItems = items.map { item in
      CleanupItem(
        path: item.path,
        sizeBytes: item.size,
        category: item.category.rawValue
      )
    }

    // Check cancellation before Downloads scan
    if Task.isCancelled { throw CancellationError() }

    onPhase?("Scanning Downloads...")
    let downloadsFiles = await scanDownloadsDirectory()

    // Check cancellation
    if Task.isCancelled { throw CancellationError() }

    // Cache the results (only if not cancelled)
    await InsightsCacheStore.shared.cache(
      downloadsFiles: downloadsFiles,
      cleanupItems: cleanupItems,
      installedApps: installedApps
    )

    let context = RecommendationContext(
      systemMetrics: systemMetrics,
      cleanupItems: cleanupItems,
      downloadsFiles: downloadsFiles,
      installedApps: installedApps,
      currentDate: Date()
    )

    onPhase?("Evaluating rules...")
    let recommendations = try await evaluate(context: context)
    return EvaluationResult(recommendations: recommendations, isCacheHit: false, cacheAge: nil)
  }

  // MARK: - Context Building

  /// Gets system metrics (always fresh, no cache).
  private func getSystemMetrics() async throws -> SystemMetrics {
    let monitor = SystemMonitor.shared
    let metrics = try await monitor.getMetrics()

    return SystemMetrics(
      cpuUsage: metrics.cpuUsage,
      memoryUsage: metrics.memoryUsage,
      memoryUsedBytes: metrics.memoryUsed,
      memoryTotalBytes: metrics.memoryTotal,
      diskUsage: metrics.diskUsage,
      diskUsedBytes: metrics.diskUsed,
      diskTotalBytes: metrics.diskTotal,
      diskFreeBytes: metrics.diskTotal - metrics.diskUsed
    )
  }

  /// Builds a default context by querying system state (legacy, for backward compatibility).
  public func buildDefaultContext() async throws -> RecommendationContext {
    let systemMetrics = try await getSystemMetrics()

    let cleanupEngine = CleanupEngine.shared
    let items = try await cleanupEngine.scanForCleanableItems()
    let cleanupItems = items.map { item in
      CleanupItem(
        path: item.path,
        sizeBytes: item.size,
        category: item.category.rawValue
      )
    }

    let downloadsFiles = await scanDownloadsDirectory()

    return RecommendationContext(
      systemMetrics: systemMetrics,
      cleanupItems: cleanupItems,
      downloadsFiles: downloadsFiles,
      installedApps: nil,
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
    register(rule: BuildArtifactsRule())
  }

  /// Async, cancellable Downloads directory scan
  private func scanDownloadsDirectory() async -> [FileInfo] {
    let fm = FileManager.default
    let downloadsPath = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

    guard fm.fileExists(atPath: downloadsPath.path) else { return [] }

    // Collect URLs synchronously first (Swift 6 enumerator limitation)
    let urls: [URL]
    do {
      urls = try fm.contentsOfDirectory(
        at: downloadsPath,
        includingPropertiesForKeys: [
          .fileSizeKey, .creationDateKey, .contentAccessDateKey,
          .contentModificationDateKey, .isDirectoryKey,
        ],
        options: [.skipsHiddenFiles]
      )
    } catch {
      return []
    }

    var files: [FileInfo] = []

    for url in urls {
      // Cancellation check
      if Task.isCancelled { return [] }

      guard
        let resourceValues = try? url.resourceValues(forKeys: [
          .fileSizeKey, .creationDateKey, .contentAccessDateKey,
          .contentModificationDateKey, .isDirectoryKey,
        ])
      else { continue }

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

    return files
  }
}
