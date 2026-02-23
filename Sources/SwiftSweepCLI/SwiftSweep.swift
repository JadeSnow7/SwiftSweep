import ArgumentParser
import Foundation

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

@main
struct SwiftSweep: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "SwiftSweep - Professional macOS System Optimizer",
    subcommands: [
      Clean.self,
      Analyze.self,
      Optimize.self,
      Status.self,
      Peripherals.self,
      Diagnostics.self,
      Uninstall.self,
      Insights.self
    ],
    defaultSubcommand: Status.self
  )
}

private enum CLIAsyncBridgeError: Error {
  case missingResult
}

private final class CLIAsyncResultBox<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<T, Error>?

  func set(_ result: Result<T, Error>) {
    lock.lock()
    self.result = result
    lock.unlock()
  }

  func get() -> Result<T, Error>? {
    lock.lock()
    defer { lock.unlock() }
    return result
  }
}

private func awaitAsync<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
  let semaphore = DispatchSemaphore(value: 0)
  let resultBox = CLIAsyncResultBox<T>()

  Task {
    do {
      let value = try await operation()
      resultBox.set(.success(value))
    } catch {
      resultBox.set(.failure(error))
    }
    semaphore.signal()
  }

  semaphore.wait()

  guard let result = resultBox.get() else {
    throw CLIAsyncBridgeError.missingResult
  }

  return try result.get()
}

struct Clean: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Deep system cleanup to free up disk space"
  )

  @Flag(name: .long, help: "Preview cleanup without deleting") var dryRun = false

  @Option(name: .long, help: "Filter by category: cache, logs, browser, system") var category: String?

  @Flag(name: .long, help: "Output as JSON") var json = false

  mutating func run() throws {
    var items: [CleanupEngine.CleanupItem]

    print("🔍 Scanning for cleanable items...")

    do {
      items = try awaitAsync {
        try await CleanupEngine.shared.scanForCleanableItems()
      }
    } catch {
      print("❌ Error scanning: \(error)")
      return
    }

    // Filter by category if specified
    if let cat = category {
      items = items.filter { item in
        switch cat.lowercased() {
        case "cache": item.category == .userCache || item.category == .systemCache
        case "logs": item.category == .logs
        case "browser": item.category == .browserCache
        case "system": item.category == .systemCache
        default: true
        }
      }
    }

    if items.isEmpty {
      print("✨ Your system is already clean!")
      return
    }

    let totalSize = items.reduce(0) { $0 + $1.size }

    if json {
      printJSON(items: items, totalSize: totalSize)
    } else {
      printFormatted(items: items, totalSize: totalSize)
    }

    if !dryRun {
      print("\n🧹 Cleaning...")

      let cleanupItems = items
      do {
        let freedBytes = try awaitAsync {
          try await CleanupEngine.shared.performCleanup(items: cleanupItems, dryRun: false)
        }
        print("✅ Freed \(formatBytes(freedBytes))")
      } catch {
        print("❌ Error cleaning: \(error)")
      }
    } else {
      print("\n💡 Dry run mode - no files were deleted")
      print("   Run without --dry-run to actually clean")
    }
  }

  func printFormatted(items: [CleanupEngine.CleanupItem], totalSize: Int64) {
    print("\n📊 Found \(items.count) items (\(formatBytes(totalSize)) total):\n")

    // Group by category
    let grouped = Dictionary(grouping: items) { $0.category }

    for (category, categoryItems) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
      let categorySize = categoryItems.reduce(0) { $0 + $1.size }
      print("[\(category.rawValue)] - \(formatBytes(categorySize))")

      for item in categoryItems.prefix(5) {
        print("  • \(item.name) (\(formatBytes(item.size)))")
      }
      if categoryItems.count > 5 {
        print("  ... and \(categoryItems.count - 5) more items")
      }
      print("")
    }
  }

  func printJSON(items: [CleanupEngine.CleanupItem], totalSize: Int64) {
    var jsonItems: [[String: Any]] = []
    for item in items {
      jsonItems.append([
        "name": item.name,
        "path": item.path,
        "size": item.size,
        "category": item.category.rawValue
      ])
    }

    let output: [String: Any] = [
      "total_items": items.count,
      "total_size": totalSize,
      "total_size_human": formatBytes(totalSize),
      "items": jsonItems
    ]

    if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
       let str = String(data: data, encoding: .utf8)
    {
      print(str)
    }
  }

  func formatBytes(_ bytes: Int64) -> String {
    let mb = Double(bytes) / 1024 / 1024
    if mb > 1024 {
      return String(format: "%.2f GB", mb / 1024)
    }
    return String(format: "%.1f MB", mb)
  }
}

struct Analyze: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Analyze disk usage and show large files/folders"
  )

  @Argument(help: "Path to analyze (default: home directory)") var path: String?

  @Option(name: .long, help: "Number of largest items to show") var top = 10

  @Flag(name: .long, help: "Show folder sizes (tree analysis)") var tree = false

  @Flag(name: .long, help: "Output as JSON") var json = false

  mutating func run() throws {
    let targetPath = path ?? NSHomeDirectory()
    let fileManager = FileManager.default

    guard fileManager.fileExists(atPath: targetPath) else {
      printError("Path does not exist: \(targetPath)")
      return
    }

    if !json {
      print("🔍 Analyzing: \(targetPath)")
      print("   This may take a while for large directories...\n")
    }

    let showProgress = !json

    let result: AnalyzerEngine.AnalysisResult
    do {
      result = try awaitAsync {
        try await AnalyzerEngine.shared.analyze(path: targetPath) { count, _ in
          if showProgress {
            print("\r   Scanned \(count) items...", terminator: "")
            fflush(stdout)
          }
        }
      }
    } catch {
      if !json { print("") } // New line after progress
      printError("Error scanning: \(error)")
      return
    }

    if !json { print("") } // New line after progress

    if json {
      printJSON(result: result, path: targetPath)
    } else if tree, let root = result.rootNode {
      printTree(root: root)
    } else {
      printSummary(result: result, path: targetPath)
    }
  }

  func printSummary(result: AnalyzerEngine.AnalysisResult, path: String) {
    print("📊 Summary:")
    print("   Total Size:   \(formatBytes(result.totalSize))")
    print("   Files:        \(result.fileCount)")
    print("   Directories:  \(result.dirCount)")
    print("")
    print("📁 Top \(min(top, result.topFiles.count)) Largest Files:")
    print("")

    for (index, file) in result.topFiles.prefix(top).enumerated() {
      let relativePath = file.path.replacingOccurrences(of: path + "/", with: "")
      print(
        "  \(index + 1). \(formatBytes(file.size).padding(toLength: 12, withPad: " ", startingAt: 0)) \(relativePath)"
      )
    }
  }

  func printTree(root: FileNode) {
    print("📁 Folder Sizes (Top \(top)):")
    print("")

    // Get all directories sorted by size
    var folders: [FileNode] = []
    collectFolders(node: root, into: &folders)
    let topFolders = folders.sorted { $0.size > $1.size }.prefix(top)

    for (index, folder) in topFolders.enumerated() {
      let percent = root.size > 0 ? Double(folder.size) / Double(root.size) * 100 : 0
      print(
        "  \(index + 1). \(formatBytes(folder.size).padding(toLength: 12, withPad: " ", startingAt: 0)) (\(String(format: "%5.1f%%", percent))) \(folder.path)"
      )
    }
  }

  func collectFolders(node: FileNode, into array: inout [FileNode]) {
    if node.isDirectory, node.size > 0 {
      array.append(node)
      node.children?.forEach { collectFolders(node: $0, into: &array) }
    }
  }

  func printJSON(result: AnalyzerEngine.AnalysisResult, path: String) {
    var topFilesJSON: [[String: Any]] = []
    for file in result.topFiles.prefix(top) {
      topFilesJSON.append([
        "path": file.path,
        "size": file.size,
        "size_human": formatBytes(file.size)
      ])
    }

    var topFoldersJSON: [[String: Any]] = []
    if let root = result.rootNode {
      var folders: [FileNode] = []
      collectFolders(node: root, into: &folders)
      for folder in folders.sorted(by: { $0.size > $1.size }).prefix(top) {
        topFoldersJSON.append([
          "path": folder.path,
          "size": folder.size,
          "size_human": formatBytes(folder.size),
          "file_count": folder.fileCount,
          "percentage": root.size > 0 ? Double(folder.size) / Double(root.size) * 100 : 0
        ])
      }
    }

    let output: [String: Any] = [
      "path": path,
      "total_size": result.totalSize,
      "total_size_human": formatBytes(result.totalSize),
      "file_count": result.fileCount,
      "dir_count": result.dirCount,
      "top_files": topFilesJSON,
      "top_folders": topFoldersJSON
    ]

    if let data = try? JSONSerialization.data(
      withJSONObject: output, options: [.prettyPrinted, .sortedKeys]
    ),
      let str = String(data: data, encoding: .utf8)
    {
      print(str)
    }
  }

  func printError(_ message: String) {
    if json {
      print("{\"error\": \"\(message)\"}")
    } else {
      print("❌ \(message)")
    }
  }

  func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

struct Optimize: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Optimize and maintain your system"
  )

  mutating func run() throws {
    print("System optimization not yet implemented in Swift CLI")
  }
}

struct Status: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show real-time system status"
  )

  @Flag(name: .long, help: "Output as JSON") var json = false

  mutating func run() throws {
    let metrics: SystemMonitor.SystemMetrics
    do {
      metrics = try awaitAsync {
        try await SystemMonitor.shared.getMetrics()
      }
    } catch {
      print("Error fetching metrics: \(error)")
      return
    }

    let m = metrics

    if json {
      let jsonOutput = """
      {
        "cpu": \(String(format: "%.1f", m.cpuUsage)),
        "memory": {
          "used_gb": \(String(format: "%.2f", Double(m.memoryUsed) / 1_073_741_824)),
          "total_gb": \(String(format: "%.2f", Double(m.memoryTotal) / 1_073_741_824)),
          "percentage": \(String(format: "%.1f", m.memoryUsage * 100))
        },
        "disk": {
          "used_gb": \(String(format: "%.2f", Double(m.diskUsed) / 1_073_741_824)),
          "total_gb": \(String(format: "%.2f", Double(m.diskTotal) / 1_073_741_824)),
          "percentage": \(String(format: "%.1f", m.diskUsage * 100))
        },
        "battery": \(String(format: "%.1f", m.batteryLevel))
      }
      """
      print(jsonOutput)
    } else {
      print("System status:")
      print("  CPU:     \(String(format: "%.1f", m.cpuUsage))%")
      print(
        "  Memory:  \(String(format: "%.2f", Double(m.memoryUsed) / 1_073_741_824)) / \(String(format: "%.2f", Double(m.memoryTotal) / 1_073_741_824)) GB (\(String(format: "%.1f", m.memoryUsage * 100))%)"
      )
      print(
        "  Disk:    \(String(format: "%.2f", Double(m.diskUsed) / 1_073_741_824)) / \(String(format: "%.2f", Double(m.diskTotal) / 1_073_741_824)) GB (\(String(format: "%.1f", m.diskUsage * 100))%)"
      )
      print("  Battery: \(String(format: "%.0f", m.batteryLevel))%")
    }
  }
}

struct Peripherals: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Inspect connected displays and input devices"
  )

  @Flag(name: .long, help: "Output as JSON") var json = false

  @Flag(name: .long, help: "Include sensitive identifiers") var sensitive = false

  mutating func run() throws {
    let includeSensitive = sensitive
    let snapshot: PeripheralSnapshot

    do {
      snapshot = try awaitAsync {
        await PeripheralInspector.shared.getSnapshot(includeSensitive: includeSensitive)
      }
    } catch {
      print("Error fetching peripherals: \(error)")
      return
    }

    if json {
      printJSON(snapshot)
    } else {
      printFormatted(snapshot)
    }
  }

  private func printFormatted(_ snapshot: PeripheralSnapshot) {
    print("Peripherals:")
    print("  Displays: \(snapshot.displays.count)")
    if snapshot.displays.isEmpty {
      print("    - No display information available")
    } else {
      for display in snapshot.displays {
        let name = display.name ?? "Unknown Display"
        let builtIn = peripheralBuiltInLabel(display.isBuiltin)
        let resolution = [display.pixelsWidth, display.pixelsHeight]
          .compactMap { $0 }
        let resolutionText =
          resolution.count == 2 ? "\(resolution[0])x\(resolution[1])" : "N/A"
        print("    - \(name) [\(builtIn), \(resolutionText)]")
      }
    }

    print("  Input Devices: \(snapshot.inputDevices.count)")
    if snapshot.inputDevices.isEmpty {
      print("    - No input device information available")
    } else {
      for device in snapshot.inputDevices {
        let name = device.name ?? "Unknown Device"
        let transport = device.transport ?? "Unknown transport"
        print("    - \(name) [\(device.kind.rawValue), \(transport)]")
      }
    }
  }

  private func printJSON(_ snapshot: PeripheralSnapshot) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      let data = try encoder.encode(PeripheralSnapshotJSONDTO(snapshot: snapshot))
      if let text = String(data: data, encoding: .utf8) {
        print(text)
      }
    } catch {
      print("{\"error\": \"Failed to encode peripherals: \(error.localizedDescription)\"}")
    }
  }
}

func peripheralBuiltInLabel(_ isBuiltin: Bool?) -> String {
  if let isBuiltin {
    return isBuiltin ? "Built-in" : "External"
  }
  return "Unknown"
}

struct Diagnostics: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show Apple Diagnostics startup guide"
  )

  @Flag(name: .long, help: "Open Apple support article in browser") var openSupport = false

  mutating func run() throws {
    let guide = DiagnosticsGuideService.shared.getGuide()

    print("Apple Diagnostics Guide:")
    print("  Architecture: \(displayArchitecture(guide.architecture))")
    print("")
    print("Steps:")
    for (index, step) in guide.steps.enumerated() {
      print("  \(index + 1). \(step)")
    }

    if !guide.notes.isEmpty {
      print("")
      print("Notes:")
      for note in guide.notes {
        print("  - \(note)")
      }
    }

    print("")
    print("Support: \(guide.supportURL.absoluteString)")

    if openSupport {
      openURL(guide.supportURL)
    }
  }

  private func displayArchitecture(_ architecture: MachineArchitecture) -> String {
    switch architecture {
    case .appleSilicon: "Apple Silicon"
    case .intel: "Intel"
    case .unknown: "Unknown"
    }
  }

  private func openURL(_ url: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    do {
      try process.run()
      process.waitUntilExit()
      if process.terminationStatus != 0 {
        print("⚠️ Unable to open browser automatically.")
      }
    } catch {
      print("⚠️ Unable to open browser automatically: \(error.localizedDescription)")
    }
  }
}

struct Uninstall: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Uninstall applications completely"
  )

  @Argument(help: "Application name to uninstall (partial match supported)") var appName: String?

  @Flag(name: .long, help: "List all installed applications") var list = false

  @Flag(name: .long, help: "Show residual files without uninstalling") var scan = false

  @Flag(name: .long, help: "Output as JSON") var json = false

  mutating func run() throws {
    let apps: [UninstallEngine.InstalledApp]

    print("🔍 Scanning installed applications...")

    do {
      apps = try awaitAsync {
        try await UninstallEngine.shared.scanInstalledApps()
      }
    } catch {
      print("❌ Error scanning: \(error)")
      return
    }

    if list {
      printAppList(apps: apps)
      return
    }

    guard let name = appName else {
      print("Usage: swiftsweep uninstall <AppName> [--scan]")
      print("       swiftsweep uninstall --list")
      return
    }

    // Find matching apps
    let matches = apps.filter {
      $0.name.lowercased().contains(name.lowercased())
        || $0.bundleID.lowercased().contains(name.lowercased())
    }

    if matches.isEmpty {
      print("❌ No applications found matching '\(name)'")
      return
    }

    if matches.count > 1 {
      print("Found multiple matches:")
      for app in matches {
        print("  • \(app.name) (\(app.bundleID))")
      }
      print("\nPlease be more specific.")
      return
    }

    let app = matches[0]

    // Find residual files
    var residuals: [UninstallEngine.ResidualFile] = []
    do {
      residuals = try UninstallEngine.shared.findResidualFiles(for: app)
    } catch {
      print("⚠️  Could not scan residual files: \(error)")
    }

    if json {
      printAppJSON(app: app, residuals: residuals)
    } else {
      printAppDetails(app: app, residuals: residuals)
    }

    if !scan {
      print("\n⚠️  Actual uninstallation requires privileged access.")
      print("   Use --scan to preview what would be removed.")
      print("   Privileged helper (SMJobBless) not yet implemented.")
    }
  }

  func printAppList(apps: [UninstallEngine.InstalledApp]) {
    print("\n📱 Installed Applications (\(apps.count) total):\n")

    for app in apps.prefix(30) {
      let size = formatBytes(app.size)
      print("  \(size.padding(toLength: 12, withPad: " ", startingAt: 0)) \(app.name)")
    }

    if apps.count > 30 {
      print("\n  ... and \(apps.count - 30) more applications")
    }
  }

  func printAppDetails(app: UninstallEngine.InstalledApp, residuals: [UninstallEngine.ResidualFile]) {
    print("\n📦 \(app.name)")
    print("   Bundle ID:  \(app.bundleID)")
    print("   Path:       \(app.path)")
    print("   App Size:   \(formatBytes(app.size))")

    if !residuals.isEmpty {
      let residualSize = residuals.reduce(0) { $0 + $1.size }
      print("\n🗂️  Residual Files (\(formatBytes(residualSize))):")

      let grouped = Dictionary(grouping: residuals) { $0.type }
      for (type, files) in grouped {
        print("   [\(type.rawValue)]")
        for file in files {
          let name = (file.path as NSString).lastPathComponent
          print("     • \(name) (\(formatBytes(file.size)))")
        }
      }

      let total = app.size + residualSize
      print("\n   Total:      \(formatBytes(total))")
    } else {
      print("\n✨ No residual files found")
    }
  }

  func printAppJSON(app: UninstallEngine.InstalledApp, residuals: [UninstallEngine.ResidualFile]) {
    var residualItems: [[String: Any]] = []
    for file in residuals {
      residualItems.append([
        "path": file.path,
        "size": file.size,
        "type": file.type.rawValue
      ])
    }

    let output: [String: Any] = [
      "name": app.name,
      "bundle_id": app.bundleID,
      "path": app.path,
      "size": app.size,
      "residual_files": residualItems,
      "total_size": app.size + residuals.reduce(0) { $0 + $1.size }
    ]

    if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
       let str = String(data: data, encoding: .utf8)
    {
      print(str)
    }
  }

  func formatBytes(_ bytes: Int64) -> String {
    let mb = Double(bytes) / 1024 / 1024
    if mb > 1024 {
      return String(format: "%.2f GB", mb / 1024)
    } else if mb > 1 {
      return String(format: "%.1f MB", mb)
    } else {
      return String(format: "%.1f KB", Double(bytes) / 1024)
    }
  }
}

// MARK: - Insights Command

struct Insights: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Smart insights and recommendations for system optimization"
  )

  @Flag(name: .long, help: "Output as JSON") var json = false

  @Flag(name: .long, help: "Show verbose evidence details") var verbose = false

  mutating func run() throws {
    let recommendations: [Recommendation]

    if !json {
      print("🔍 Analyzing system for recommendations...")
    }

    do {
      recommendations = try awaitAsync {
        try await RecommendationEngine.shared.evaluateWithSystemContext()
      }
    } catch {
      if json {
        print("{\"error\": \"\(error.localizedDescription)\"}")
      } else {
        print("❌ Error: \(error.localizedDescription)")
      }
      return
    }

    if json {
      printJSON(recommendations: recommendations)
    } else {
      printFormatted(recommendations: recommendations)
    }
  }

  func printFormatted(recommendations: [Recommendation]) {
    if recommendations.isEmpty {
      print("\n✨ No recommendations at this time. Your system is in good shape!")
      return
    }

    print("\n📊 Found \(recommendations.count) recommendation(s):\n")

    for (index, rec) in recommendations.enumerated() {
      let icon = severityIcon(rec.severity)
      let reclaimStr = rec.estimatedReclaimBytes.map { formatBytes($0) } ?? ""

      print("\(index + 1). \(icon) \(rec.title)")
      print("   \(rec.summary)")

      if !reclaimStr.isEmpty {
        print("   💾 Potential savings: \(reclaimStr)")
      }

      print("   Risk: \(rec.risk.displayName) | Confidence: \(rec.confidence.displayName)")

      if verbose, !rec.evidence.isEmpty {
        print("   Evidence:")
        for evidence in rec.evidence.prefix(5) {
          print("     • \(evidence.label): \(evidence.value)")
        }
      }

      if !rec.actions.isEmpty {
        let actionTypes = rec.actions.map(\.type.rawValue).joined(separator: ", ")
        print("   Actions: \(actionTypes)")
      }

      print("")
    }

    print("💡 Use the GUI app or specific CLI commands to act on these recommendations.")
  }

  func printJSON(recommendations: [Recommendation]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
      let data = try encoder.encode(recommendations)
      if let str = String(data: data, encoding: .utf8) {
        print(str)
      }
    } catch {
      print("{\"error\": \"Failed to encode recommendations: \(error.localizedDescription)\"}")
    }
  }

  func severityIcon(_ severity: Severity) -> String {
    switch severity {
    case .critical: "🔴"
    case .warning: "🟡"
    case .info: "🔵"
    }
  }

  func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1 {
      return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_000_000
    return String(format: "%.1f MB", mb)
  }
}
