import Foundation

// MARK: - UnusedAppsRule

/// Detects applications that haven't been used for a long time.
public struct UnusedAppsRule: RecommendationRule {
  public let id = "unused_apps"
  public let displayName = "Unused Applications"
  public let capabilities: [RuleCapability] = [.installedApps]

  /// Days since last use to consider app as "unused" - reads from RuleSettings
  private var unusedDaysThreshold: Int {
    RuleSettings.shared.threshold(forRule: id, key: "days")
  }
  /// Minimum app size to include (bytes)
  private let minAppSize: Int64 = 50_000_000  // 50 MB
  /// Minimum total unused size to generate recommendation
  private let minTotalSize: Int64 = 500_000_000  // 500 MB

  public init() {}

  public func evaluate(context: RecommendationContext) async throws -> [Recommendation] {
    // Scan for installed apps with last used date
    let apps = try await scanInstalledApps()

    let cutoffDate =
      Calendar.current.date(byAdding: .day, value: -unusedDaysThreshold, to: context.currentDate)
      ?? context.currentDate

    // Filter unused apps
    var unusedApps: [(name: String, path: String, bundleID: String, size: Int64, lastUsed: Date?)] =
      []

    for app in apps {
      // Skip if recently used
      if let lastUsed = app.lastUsedDate, lastUsed >= cutoffDate {
        continue
      }

      // Skip small apps
      guard let size = app.sizeBytes, size >= minAppSize else { continue }

      unusedApps.append((app.name, app.path, app.bundleID, size, app.lastUsedDate))
    }

    // Sort by size descending
    unusedApps.sort { $0.size > $1.size }

    let totalSize = unusedApps.reduce(0) { $0 + $1.size }

    // Only generate if significant
    guard totalSize >= minTotalSize, !unusedApps.isEmpty else { return [] }

    // Build evidence
    var evidence: [Evidence] = [
      Evidence(kind: .aggregate, label: "Unused Apps", value: "\(unusedApps.count) apps"),
      Evidence(kind: .aggregate, label: "Total Size", value: formatBytes(totalSize)),
      Evidence(kind: .metadata, label: "Threshold", value: "\(unusedDaysThreshold) days"),
    ]

    // Add top unused apps as evidence
    for app in unusedApps.prefix(5) {
      let lastUsedStr = app.lastUsed.map { formatDate($0) } ?? "Never"
      evidence.append(
        Evidence(
          kind: .path,
          label: app.name,
          value: "\(formatBytes(app.size)) (Last: \(lastUsedStr))"
        ))
    }

    // Build actions - open Finder to Applications
    let actions: [Action] = [
      Action(
        type: .openFinder, payload: .paths(["/Applications"]), requiresConfirmation: false,
        supportsDryRun: false)
    ]

    return [
      Recommendation(
        id: id,
        title: "Unused Applications",
        summary:
          "\(unusedApps.count) apps not used in \(unusedDaysThreshold)+ days, totaling \(formatBytes(totalSize)).",
        severity: .info,
        risk: .medium,  // Uninstalling apps is more risky
        confidence: .medium,  // Last used date may not be accurate
        estimatedReclaimBytes: totalSize,
        evidence: evidence,
        actions: actions,
        requirements: []
      )
    ]
  }

  private func scanInstalledApps() async throws -> [AppInfo] {
    let fm = FileManager.default
    let applicationsPath = "/Applications"

    guard let contents = try? fm.contentsOfDirectory(atPath: applicationsPath) else {
      return []
    }

    var apps: [AppInfo] = []

    for item in contents where item.hasSuffix(".app") {
      let appPath = (applicationsPath as NSString).appendingPathComponent(item)
      let appURL = URL(fileURLWithPath: appPath)

      // Get bundle info
      guard let bundle = Bundle(url: appURL),
        let bundleID = bundle.bundleIdentifier
      else { continue }

      let name = (item as NSString).deletingPathExtension

      // Get size
      let size = calculateDirectorySize(at: appURL)

      // Get last used date from Spotlight metadata
      let lastUsed = getLastUsedDate(for: appPath)

      apps.append(
        AppInfo(
          bundleID: bundleID,
          name: name,
          path: appPath,
          sizeBytes: size,
          lastUsedDate: lastUsed
        ))
    }

    return apps
  }

  private func getLastUsedDate(for path: String) -> Date? {
    // Try to get kMDItemLastUsedDate from Spotlight
    let url = URL(fileURLWithPath: path)

    if let resourceValues = try? url.resourceValues(forKeys: [.contentAccessDateKey]),
      let accessDate = resourceValues.contentAccessDate
    {
      return accessDate
    }

    return nil
  }

  private func calculateDirectorySize(at url: URL) -> Int64 {
    let fm = FileManager.default
    var size: Int64 = 0

    guard
      let enumerator = fm.enumerator(
        at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
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

  private func formatDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}
