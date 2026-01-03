import Foundation
import Logging

/// MoleKit 清理引擎 - 负责文件清理、扫描、和删除操作
public final class CleanupEngine {
  public static let shared = CleanupEngine()

  private let logger = Logger(label: "com.molekit.cleanup")

  public struct CleanupItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let path: String
    public let size: Int64
    public let itemCount: Int
    public let category: CleanupCategory
    public var isSelected: Bool = true

    public init(name: String, path: String, size: Int64, itemCount: Int, category: CleanupCategory)
    {
      self.id = UUID()
      self.name = name
      self.path = path
      self.size = size
      self.itemCount = itemCount
      self.category = category
    }
  }

  public enum CleanupCategory: String, Codable, Sendable {
    case userCache = "User Cache"
    case systemCache = "System Cache"
    case logs = "Logs"
    case trash = "Trash"
    case browserCache = "Browser Cache"
    case developerTools = "Developer Tools"
    case applications = "Applications"
    case other = "Other"
  }

  // MARK: - Properties

  private var privilegedDeleter: PrivilegedDeleting?

  /// Result structure for granular reporting
  public struct CleanupResultItem: Sendable {
    public let originalPath: String
    public let canonicalPath: String
    public let size: Int64
    public let outcome: Outcome

    public enum Outcome: Sendable {
      case deleted
      case deletedPrivileged
      case skippedDryRun
      case failed(reason: String)
    }
  }

  public init(privilegedDeleter: PrivilegedDeleting? = nil) {
    if #available(macOS 13.0, *) {
      self.privilegedDeleter = privilegedDeleter ?? HelperClient.shared
    } else {
      self.privilegedDeleter = privilegedDeleter
    }
  }

  /// 扫描可清理的项目
  public func scanForCleanableItems() async throws -> [CleanupItem] {
    logger.info("Starting cleanup scan...")

    var items: [CleanupItem] = []

    // 扫描用户缓存
    items.append(contentsOf: try scanUserCache())

    // 扫描浏览器缓存
    items.append(contentsOf: try scanBrowserCache())

    // 扫描系统缓存
    items.append(contentsOf: try scanSystemCache())

    // 扫描日志
    items.append(contentsOf: try scanLogs())

    logger.info("Scan complete. Found \(items.count) cleanable items")
    return items
  }

  /// 执行清理操作 (Legacy wrapper returning total bytes)
  @discardableResult
  public func performCleanup(items: [CleanupItem], dryRun: Bool = false) async throws -> Int64 {
    let results = await performRobustCleanup(items: items, dryRun: dryRun)

    let freedBytes = results.reduce(0 as Int64) { total, result in
      switch result.outcome {
      case .deleted, .deletedPrivileged:
        return total + result.size
      case .skippedDryRun:
        return total + (dryRun ? result.size : 0)  // Count potential size
      case .failed:
        return total
      }
    }
    return freedBytes
  }

  /// 执行健壮清理操作
  public func performRobustCleanup(items: [CleanupItem], dryRun: Bool = false) async
    -> [CleanupResultItem]
  {
    // Use simple track since this function doesn't throw
    let start = mach_absolute_time()
    logger.info("Starting robust cleanup. Dry run: \(dryRun)")

    var results: [CleanupResultItem] = []

    for item in items where item.isSelected {
      if Task.isCancelled { break }
      let result = await deleteItemChecked(item, dryRun: dryRun)
      results.append(result)
    }

    // Record metrics manually
    let end = mach_absolute_time()
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let nanos = (end - start) * UInt64(info.numer) / UInt64(info.denom)

    await PerformanceMonitor.shared.record(
      OperationMetrics(
        operationName: "cleanup.robust",
        startTicks: start,
        endTicks: end,
        durationNanos: nanos,
        itemsProcessed: results.count,
        bytesProcessed: results.reduce(0) { $0 + $1.size },
        outcome: Task.isCancelled ? .cancelled : .success
      )
    )

    return results
  }

  private func deleteItemChecked(_ item: CleanupItem, dryRun: Bool) async -> CleanupResultItem {
    let path = item.path
    let url = URL(fileURLWithPath: path)
    let standardizedURL = url.standardized
    let canonicalPath = standardizedURL.path

    // 1. Safety Checks
    guard !canonicalPath.isEmpty, canonicalPath != "/" else {
      return CleanupResultItem(
        originalPath: path, canonicalPath: canonicalPath, size: item.size,
        outcome: .failed(reason: "Invalid path"))
    }

    // 2. Dry Run
    if dryRun {
      logger.debug("Would delete: \(canonicalPath)")
      return CleanupResultItem(
        originalPath: path, canonicalPath: canonicalPath, size: item.size, outcome: .skippedDryRun)
    }

    // 3. Attempt Standard Delete
    do {
      try FileManager.default.removeItem(at: standardizedURL)
      logger.debug("Deleted (Standard): \(canonicalPath)")
      return CleanupResultItem(
        originalPath: path, canonicalPath: canonicalPath, size: item.size, outcome: .deleted)
    } catch {
      // 4. Check for Escalation
      if shouldEscalate(error: error) {
        return await attemptPrivilegedDelete(
          item: item, url: standardizedURL, canonicalPath: canonicalPath)
      } else {
        logger.error("Failed to delete \(canonicalPath): \(error)")
        return CleanupResultItem(
          originalPath: path, canonicalPath: canonicalPath, size: item.size,
          outcome: .failed(reason: error.localizedDescription))
      }
    }
  }

  private func attemptPrivilegedDelete(item: CleanupItem, url: URL, canonicalPath: String) async
    -> CleanupResultItem
  {
    // Pre-check: Verify path is in allowlist (same rules as Helper)
    guard CleanupAllowlist.isTargetAllowed(canonicalPath) else {
      logger.warning("Path not in allowlist, skipping Helper: \(canonicalPath)")
      return CleanupResultItem(
        originalPath: item.path, canonicalPath: canonicalPath, size: item.size,
        outcome: .failed(reason: "Path not in allowed list"))
    }

    guard let deleter = privilegedDeleter else {
      return CleanupResultItem(
        originalPath: item.path, canonicalPath: canonicalPath, size: item.size,
        outcome: .failed(reason: "Permission denied (Helper unavailable)"))
    }

    do {
      try await deleter.deleteItem(at: url)

      // Verify Deletion
      if FileManager.default.fileExists(atPath: canonicalPath) {
        return CleanupResultItem(
          originalPath: item.path, canonicalPath: canonicalPath, size: item.size,
          outcome: .failed(reason: "Helper reported success but file exists"))
      }

      logger.info("Deleted (Privileged): \(canonicalPath)")
      return CleanupResultItem(
        originalPath: item.path, canonicalPath: canonicalPath, size: item.size,
        outcome: .deletedPrivileged)
    } catch {
      logger.error("Privileged delete failed \(canonicalPath): \(error)")
      return CleanupResultItem(
        originalPath: item.path, canonicalPath: canonicalPath, size: item.size,
        outcome: .failed(reason: "Privileged delete failed: \(error.localizedDescription)"))
    }
  }

  private func shouldEscalate(error: Error) -> Bool {
    let nsError = error as NSError

    // Cocoa Errors
    if nsError.domain == NSCocoaErrorDomain {
      if nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError
      {
        return true
      }
    }

    // POSIX Errors
    if nsError.domain == NSPOSIXErrorDomain {
      // EACCES (13): Permission denied
      // EPERM (1): Operation not permitted
      if nsError.code == 13 || nsError.code == 1 {
        return true
      }
      // EROFS (30): Read-only file system - DO NOT ESCALATE
      if nsError.code == 30 {
        return false
      }
    }

    return false
  }

  // MARK: - Private Scanning Methods

  private func scanUserCache() throws -> [CleanupItem] {
    var items: [CleanupItem] = []
    let fileManager = FileManager.default

    // 1. User Caches (~/Library/Caches)
    if let cachesPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
      .first
    {
      let cacheItems = try scanDirectory(at: cachesPath, category: .userCache)
      items.append(contentsOf: cacheItems)
    }

    // 2. User Logs (~/Library/Logs)
    if let logsPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)
      .first
    {
      let userLogs = logsPath + "/Logs"
      let logItems = try scanDirectory(at: userLogs, category: .logs)
      items.append(contentsOf: logItems)
    }

    // 3. User Trash (~/.Trash)
    let trashPath = NSHomeDirectory() + "/.Trash"
    if fileManager.fileExists(atPath: trashPath) {
      let trashItems = try scanDirectory(at: trashPath, category: .trash)
      items.append(contentsOf: trashItems)
    }

    return items
  }

  private func scanDirectory(at path: String, category: CleanupCategory) throws -> [CleanupItem] {
    let fileManager = FileManager.default
    var items: [CleanupItem] = []

    guard let subpaths = try? fileManager.contentsOfDirectory(atPath: path) else {
      return []
    }

    for subpath in subpaths {
      // Skip hidden files or system files if needed
      if subpath.hasPrefix(".") && subpath != ".Trash" { continue }

      let fullPath = path + "/" + subpath
      guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath) else { continue }

      let size = attrs[.size] as? Int64 ?? 0
      var totalSize = size
      var count = 1

      if let type = attrs[.type] as? FileAttributeType, type == .typeDirectory {
        // Single pass: get both size and count
        (totalSize, count) = calculateDirectorySizeAndCount(at: fullPath)
      }

      // Only list items > 1KB to reduce noise
      if totalSize > 1024 {
        let item = CleanupItem(
          name: subpath,
          path: fullPath,
          size: totalSize,
          itemCount: count,
          category: category
        )
        items.append(item)
      }
    }

    return items
  }

  /// Single-pass directory enumeration returning (totalSize, fileCount)
  /// Counts only files (not directories), excludes hidden files
  private func calculateDirectorySizeAndCount(at path: String) -> (Int64, Int) {
    let url = URL(fileURLWithPath: path)
    let fm = FileManager.default
    var size: Int64 = 0
    var count: Int = 0

    guard
      let enumerator = fm.enumerator(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return (0, 0)
    }

    for case let fileURL as URL in enumerator {
      if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
        values.isDirectory != true
      {
        size += Int64(values.fileSize ?? 0)
        count += 1
      }
    }

    return (size, count)
  }

  /// Legacy wrapper for size-only callers
  private func calculateDirectorySize(at path: String) -> Int64 {
    return calculateDirectorySizeAndCount(at: path).0
  }

  private func scanBrowserCache() throws -> [CleanupItem] {
    var items: [CleanupItem] = []
    let fileManager = FileManager.default
    let home = NSHomeDirectory()

    // 1. Google Chrome
    let chromePath = home + "/Library/Caches/Google/Chrome"
    if fileManager.fileExists(atPath: chromePath) {
      items.append(contentsOf: try scanDirectory(at: chromePath, category: .browserCache))
    }

    // 2. Safari
    let safariPath = home + "/Library/Caches/com.apple.Safari"
    if fileManager.fileExists(atPath: safariPath) {
      let (size, count) = calculateDirectorySizeAndCount(at: safariPath)
      let item = CleanupItem(
        name: "Safari Cache",
        path: safariPath,
        size: size,
        itemCount: count,
        category: .browserCache
      )
      items.append(item)
    }

    // 3. Firefox
    let firefoxPath = home + "/Library/Caches/Firefox"
    if fileManager.fileExists(atPath: firefoxPath) {
      items.append(contentsOf: try scanDirectory(at: firefoxPath, category: .browserCache))
    }

    return items
  }

  private func scanSystemCache() throws -> [CleanupItem] {
    var items: [CleanupItem] = []
    let fileManager = FileManager.default

    // Scan ~/Library/Caches for com.apple.*
    if let cachesPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
      .first
    {
      guard let subpaths = try? fileManager.contentsOfDirectory(atPath: cachesPath) else {
        return []
      }

      for subpath in subpaths {
        if subpath.starts(with: "com.apple.") {
          let fullPath = cachesPath + "/" + subpath
          let (size, count) = calculateDirectorySizeAndCount(at: fullPath)

          if size > 1024 * 1024 {  // Only show system caches > 1MB
            let item = CleanupItem(
              name: subpath,
              path: fullPath,
              size: size,
              itemCount: count,
              category: .systemCache
            )
            items.append(item)
          }
        }
      }
    }

    return items
  }

  private func scanLogs() throws -> [CleanupItem] {
    var items: [CleanupItem] = []

    // Setup standard log paths
    let logPaths = [
      NSHomeDirectory() + "/Library/Logs",
      "/Library/Logs",  // System logs (might require recursion/permissions, but good to list)
    ]

    for path in logPaths {
      items.append(contentsOf: try scanDirectory(at: path, category: .logs))
    }

    return items
  }
}
