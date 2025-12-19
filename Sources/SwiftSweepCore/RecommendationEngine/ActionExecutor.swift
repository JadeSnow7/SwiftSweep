import Foundation

// MARK: - ActionExecutor

/// Unified executor for cleanup actions with deduplication, dry-run support,
/// per-item result tracking, cancellation, and logging.
public actor ActionExecutor {
  public static let shared = ActionExecutor()

  // MARK: - Types

  public struct ExecutionResult: Sendable {
    public let successCount: Int
    public let failedCount: Int
    public let skippedCount: Int
    public let totalBytes: Int64
    public let itemResults: [ItemResult]

    public var summary: String {
      let formatter = ByteCountFormatter()
      formatter.countStyle = .file
      let sizeStr = formatter.string(fromByteCount: totalBytes)
      return
        "\(successCount) moved to Trash, \(failedCount) failed, \(skippedCount) skipped (est. \(sizeStr))"
    }
  }

  public struct ItemResult: Sendable {
    public let path: String
    public let status: ItemStatus
    public let size: Int64
    public let error: String?
  }

  public enum ItemStatus: String, Sendable {
    case success
    case failed
    case skipped
  }

  public enum ExecutionMode: Sendable {
    case trash  // Move to Trash (reversible)
    case delete  // Permanent delete (not recommended)
  }

  // MARK: - Execution

  /// Execute cleanup on a set of paths with deduplication
  /// - Parameters:
  ///   - paths: Paths to clean
  ///   - mode: trash or delete
  ///   - dryRun: If true, only calculate what would happen
  ///   - ruleId: For logging
  ///   - onProgress: Progress callback (current, total)
  public func execute(
    paths: [String],
    mode: ExecutionMode = .trash,
    dryRun: Bool = false,
    ruleId: String = "manual",
    onProgress: ((Int, Int) -> Void)? = nil
  ) async -> ExecutionResult {
    let fm = FileManager.default

    // Step 1: Deduplicate and normalize paths
    let normalizedPaths = deduplicatePaths(paths)

    // Step 2: Calculate sizes
    var itemResults: [ItemResult] = []
    var totalBytes: Int64 = 0
    var successCount = 0
    var failedCount = 0
    var skippedCount = 0

    for (index, path) in normalizedPaths.enumerated() {
      onProgress?(index, normalizedPaths.count)

      guard fm.fileExists(atPath: path) else {
        itemResults.append(ItemResult(path: path, status: .skipped, size: 0, error: "Not found"))
        skippedCount += 1
        continue
      }

      let size = calculateSize(path)

      if dryRun {
        itemResults.append(ItemResult(path: path, status: .success, size: size, error: nil))
        successCount += 1
        totalBytes += size
        continue
      }

      // Execute
      do {
        switch mode {
        case .trash:
          try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        case .delete:
          try fm.removeItem(atPath: path)
        }
        itemResults.append(ItemResult(path: path, status: .success, size: size, error: nil))
        successCount += 1
        totalBytes += size
      } catch {
        itemResults.append(
          ItemResult(path: path, status: .failed, size: 0, error: error.localizedDescription))
        failedCount += 1
      }
    }

    onProgress?(normalizedPaths.count, normalizedPaths.count)

    // Log if not dry run
    if !dryRun {
      ActionLogger.shared.logCleanup(
        ruleId: ruleId,
        paths: normalizedPaths,
        totalSize: totalBytes,
        success: failedCount == 0,
        itemsMoved: successCount
      )
    }

    return ExecutionResult(
      successCount: successCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
      totalBytes: totalBytes,
      itemResults: itemResults
    )
  }

  /// Execute batch cleanup for multiple recommendations
  public func executeBatch(
    recommendations: [Recommendation],
    mode: ExecutionMode = .trash,
    dryRun: Bool = false,
    onProgress: ((Int, Int, String) -> Void)? = nil
  ) async -> ExecutionResult {
    // Collect all paths from recommendations
    var allPaths: [String] = []
    for rec in recommendations {
      for action in rec.actions {
        if action.type == .cleanupTrash || action.type == .cleanupDelete,
          case .paths(let paths) = action.payload
        {
          allPaths.append(contentsOf: paths)
        }
      }
    }

    // Execute with progress wrapper
    let result = await execute(
      paths: allPaths,
      mode: mode,
      dryRun: dryRun,
      ruleId: "batch_\(recommendations.count)_rules"
    ) { current, total in
      let currentItem =
        allPaths.indices.contains(current) ? (allPaths[current] as NSString).lastPathComponent : ""
      onProgress?(current, total, currentItem)
    }

    // Log batch
    if !dryRun {
      ActionLogger.shared.logBatchCleanup(
        recommendationCount: recommendations.count,
        totalPaths: allPaths.count,
        totalSize: result.totalBytes,
        itemsMoved: result.successCount
      )
    }

    return result
  }

  // MARK: - Private

  /// Deduplicate paths: remove child paths if parent is included
  private func deduplicatePaths(_ paths: [String]) -> [String] {
    let uniquePaths = Set(paths.map { URL(fileURLWithPath: $0).standardized.path })
    let sortedPaths = uniquePaths.sorted()

    var result: [String] = []
    for path in sortedPaths {
      let isChild = result.contains { parent in
        path.hasPrefix(parent + "/")
      }
      if !isChild {
        result.append(path)
      }
    }
    return result
  }

  /// Calculate size for path (recursive for directories)
  private nonisolated func calculateSize(_ path: String) -> Int64 {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }

    if isDir.boolValue {
      guard
        let enumerator = fm.enumerator(
          at: URL(fileURLWithPath: path),
          includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
          options: []
        )
      else { return 0 }

      var total: Int64 = 0
      for case let fileURL as URL in enumerator {
        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
          let isFile = values.isRegularFile, isFile,
          let size = values.fileSize
        {
          total += Int64(size)
        }
      }
      return total
    } else {
      if let attrs = try? fm.attributesOfItem(atPath: path),
        let size = attrs[.size] as? Int64
      {
        return size
      }
      return 0
    }
  }
}
