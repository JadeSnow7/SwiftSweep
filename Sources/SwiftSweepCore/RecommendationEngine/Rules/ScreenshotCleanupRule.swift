import Foundation

// MARK: - ScreenshotCleanupRule

/// Detects old screenshots and temporary files on Desktop.
public struct ScreenshotCleanupRule: RecommendationRule {
  public let id = "screenshot_cleanup"
  public let displayName = "Screenshot Cleanup"
  public let capabilities: [RuleCapability] = [.downloadsAccess]

  /// Days to consider screenshot as "old"
  private let ageDaysThreshold: Int = 14
  /// Minimum total size to generate recommendation
  private let minTotalSize: Int64 = 20_000_000  // 20 MB

  /// Screenshot patterns
  private let screenshotPatterns = [
    "Screenshot ",
    "Screen Shot ",
    "截屏",
    "屏幕快照",
    "Bildschirmfoto",
    "Capture d'écran",
  ]

  /// Temp file extensions
  private let tempExtensions = [
    "tmp", "temp", "download", "crdownload", "part",
  ]

  public init() {}

  public func evaluate(context: RecommendationContext) async throws -> [Recommendation] {
    let fm = FileManager.default
    let desktopPath = fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

    guard fm.fileExists(atPath: desktopPath.path) else { return [] }

    let cutoffDate =
      Calendar.current.date(byAdding: .day, value: -ageDaysThreshold, to: context.currentDate)
      ?? context.currentDate

    var screenshots: [FileInfo] = []
    var tempFiles: [FileInfo] = []

    do {
      let contents = try fm.contentsOfDirectory(
        at: desktopPath,
        includingPropertiesForKeys: [
          .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey,
        ])

      for url in contents {
        let resourceValues = try url.resourceValues(forKeys: [
          .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey,
        ])

        // Skip directories
        if resourceValues.isDirectory == true { continue }

        let filename = url.lastPathComponent
        let fileDate = resourceValues.creationDate ?? resourceValues.contentModificationDate
        let size = Int64(resourceValues.fileSize ?? 0)

        // Check if old
        guard let date = fileDate, date < cutoffDate else { continue }

        let fileInfo = FileInfo(
          path: url.path,
          name: filename,
          sizeBytes: size,
          creationDate: resourceValues.creationDate,
          contentModificationDate: resourceValues.contentModificationDate
        )

        // Check if screenshot
        if isScreenshot(filename: filename) {
          screenshots.append(fileInfo)
          continue
        }

        // Check if temp file
        if isTempFile(filename: filename) {
          tempFiles.append(fileInfo)
        }
      }
    } catch {
      return []
    }

    let allFiles = screenshots + tempFiles
    let totalSize = allFiles.reduce(0) { $0 + $1.sizeBytes }

    guard totalSize >= minTotalSize, !allFiles.isEmpty else { return [] }

    // Build evidence
    var evidence: [Evidence] = [
      Evidence(kind: .aggregate, label: "Old Screenshots", value: "\(screenshots.count) files"),
      Evidence(kind: .aggregate, label: "Temp Files", value: "\(tempFiles.count) files"),
      Evidence(kind: .aggregate, label: "Total Size", value: formatBytes(totalSize)),
    ]

    // Add some file names
    for file in allFiles.prefix(5) {
      evidence.append(
        Evidence(
          kind: .path,
          label: file.name,
          value: formatBytes(file.sizeBytes)
        ))
    }

    // Build actions
    let paths = allFiles.map { $0.path }
    let actions: [Action] = [
      Action(
        type: .cleanupTrash, payload: .paths(paths), requiresConfirmation: true,
        supportsDryRun: true),
      Action(
        type: .openFinder, payload: .paths([desktopPath.path]), requiresConfirmation: false,
        supportsDryRun: false),
    ]

    return [
      Recommendation(
        id: id,
        title: "Old Screenshots & Temp Files",
        summary:
          "\(allFiles.count) files on Desktop older than \(ageDaysThreshold) days (\(formatBytes(totalSize))).",
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

  private func isScreenshot(filename: String) -> Bool {
    // Check patterns
    for pattern in screenshotPatterns {
      if filename.hasPrefix(pattern) {
        return true
      }
    }

    // Check common screenshot extensions with naming
    let lower = filename.lowercased()
    return (lower.contains("screenshot") || lower.contains("screen shot"))
      && (lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg"))
  }

  private func isTempFile(filename: String) -> Bool {
    let ext = (filename as NSString).pathExtension.lowercased()
    return tempExtensions.contains(ext)
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
