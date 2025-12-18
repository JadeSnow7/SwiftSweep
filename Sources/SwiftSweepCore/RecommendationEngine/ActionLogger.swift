import Foundation
import os.log

// MARK: - ActionLogger

/// Logs all cleanup actions to a file for auditing.
public final class ActionLogger: @unchecked Sendable {
  public static let shared = ActionLogger()

  private let logger = Logger(subsystem: "com.swiftsweep.actionlog", category: "cleanup")
  private let logFileURL: URL
  private let queue = DispatchQueue(label: "com.swiftsweep.actionlogger", qos: .utility)

  private init() {
    let fm = FileManager.default
    let logsDir = fm.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/SwiftSweep")

    try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

    logFileURL = logsDir.appendingPathComponent("cleanup_actions.log")
  }

  /// Log a cleanup action
  public func log(action: ActionLogEntry) {
    queue.async { [weak self] in
      self?.writeLog(action)
    }
  }

  /// Log multiple items being cleaned
  public func logCleanup(
    ruleId: String,
    paths: [String],
    totalSize: Int64,
    success: Bool,
    itemsMoved: Int
  ) {
    let entry = ActionLogEntry(
      timestamp: Date(),
      ruleId: ruleId,
      actionType: "cleanupTrash",
      itemCount: paths.count,
      totalBytes: totalSize,
      success: success,
      itemsProcessed: itemsMoved,
      error: nil
    )
    log(action: entry)
  }

  /// Log batch cleanup
  public func logBatchCleanup(
    recommendationCount: Int,
    totalPaths: Int,
    totalSize: Int64,
    itemsMoved: Int
  ) {
    let entry = ActionLogEntry(
      timestamp: Date(),
      ruleId: "batch_cleanup",
      actionType: "batchCleanup",
      itemCount: totalPaths,
      totalBytes: totalSize,
      success: true,
      itemsProcessed: itemsMoved,
      error: nil
    )
    log(action: entry)
    logger.info(
      "Batch cleanup: \(recommendationCount) recommendations, \(itemsMoved) items moved, \(totalSize) bytes freed"
    )
  }

  private func writeLog(_ entry: ActionLogEntry) {
    let formatter = ISO8601DateFormatter()
    let line =
      "\(formatter.string(from: entry.timestamp)) | " + "\(entry.ruleId) | \(entry.actionType) | "
      + "items:\(entry.itemCount) | processed:\(entry.itemsProcessed) | "
      + "bytes:\(entry.totalBytes) | success:\(entry.success)\n"

    if let data = line.data(using: .utf8) {
      if FileManager.default.fileExists(atPath: logFileURL.path) {
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
          handle.seekToEndOfFile()
          handle.write(data)
          try? handle.close()
        }
      } else {
        try? data.write(to: logFileURL)
      }
    }

    logger.debug("Action logged: \(entry.ruleId) - \(entry.itemsProcessed) items")
  }

  /// Get log file path
  public var logFilePath: String {
    logFileURL.path
  }

  /// Get recent log entries
  public func getRecentLogs(limit: Int = 50) -> [String] {
    guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
      return []
    }
    let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
    return Array(lines.suffix(limit))
  }
}

// MARK: - ActionLogEntry

public struct ActionLogEntry: Codable, Sendable {
  public let timestamp: Date
  public let ruleId: String
  public let actionType: String
  public let itemCount: Int
  public let totalBytes: Int64
  public let success: Bool
  public let itemsProcessed: Int
  public let error: String?

  public init(
    timestamp: Date,
    ruleId: String,
    actionType: String,
    itemCount: Int,
    totalBytes: Int64,
    success: Bool,
    itemsProcessed: Int,
    error: String?
  ) {
    self.timestamp = timestamp
    self.ruleId = ruleId
    self.actionType = actionType
    self.itemCount = itemCount
    self.totalBytes = totalBytes
    self.success = success
    self.itemsProcessed = itemsProcessed
    self.error = error
  }
}
