import Foundation
import ArgumentParser
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
            Uninstall.self,
        ],
        defaultSubcommand: Status.self
    )
}

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Deep system cleanup to free up disk space"
    )
    
    @Flag(name: .long, help: "Preview cleanup without deleting")
    var dryRun = false
    
    @Option(name: .long, help: "Filter by category: cache, logs, browser, system")
    var category: String?
    
    @Flag(name: .long, help: "Output as JSON")
    var json = false
    
    mutating func run() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var items: [CleanupEngine.CleanupItem] = []
        var scanError: Error?
        
        print("🔍 Scanning for cleanable items...")
        
        Task {
            do {
                items = try await CleanupEngine.shared.scanForCleanableItems()
            } catch {
                scanError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = scanError {
            print("❌ Error scanning: \(error)")
            return
        }
        
        // Filter by category if specified
        if let cat = category {
            items = items.filter { item in
                switch cat.lowercased() {
                case "cache": return item.category == .userCache || item.category == .systemCache
                case "logs": return item.category == .logs
                case "browser": return item.category == .browserCache
                case "system": return item.category == .systemCache
                default: return true
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
            
            var freedBytes: Int64 = 0
            var cleanError: Error?
            
            Task {
                do {
                    freedBytes = try await CleanupEngine.shared.performCleanup(items: items, dryRun: false)
                } catch {
                    cleanError = error
                }
                semaphore.signal()
            }
            
            semaphore.wait()
            
            if let error = cleanError {
                print("❌ Error cleaning: \(error)")
            } else {
                print("✅ Freed \(formatBytes(freedBytes))")
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
           let str = String(data: data, encoding: .utf8) {
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
    
    @Argument(help: "Path to analyze (default: home directory)")
    var path: String?
    
    @Option(name: .long, help: "Number of largest items to show")
    var top: Int = 10
    
    @Flag(name: .long, help: "Show folder sizes (tree analysis)")
    var tree = false
    
    @Flag(name: .long, help: "Output as JSON")
    var json = false
    
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
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: AnalyzerEngine.AnalysisResult?
        var scanError: Error?
        let showProgress = !json
        
        Task {
            do {
                result = try await AnalyzerEngine.shared.analyze(path: targetPath) { count, size in
                    if showProgress {
                        print("\r   Scanned \(count) items...", terminator: "")
                        fflush(stdout)
                    }
                }
            } catch {
                scanError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if !json { print("") } // New line after progress
        
        if let error = scanError {
            printError("Error scanning: \(error)")
            return
        }
        
        guard let r = result else {
            printError("Analysis failed")
            return
        }
        
        if json {
            printJSON(result: r, path: targetPath)
        } else if tree, let root = r.rootNode {
            printTree(root: root)
        } else {
            printSummary(result: r, path: targetPath)
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
            print("  \(index + 1). \(formatBytes(file.size).padding(toLength: 12, withPad: " ", startingAt: 0)) \(relativePath)")
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
            print("  \(index + 1). \(formatBytes(folder.size).padding(toLength: 12, withPad: " ", startingAt: 0)) (\(String(format: "%5.1f%%", percent))) \(folder.path)")
        }
    }
    
    func collectFolders(node: FileNode, into array: inout [FileNode]) {
        if node.isDirectory && node.size > 0 {
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
        
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
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
    
    @Flag(name: .long, help: "Output as JSON")
    var json = false
    
    mutating func run() throws {
        // 使用同步方式调用异步函数
        let semaphore = DispatchSemaphore(value: 0)
        var metrics: SystemMonitor.SystemMetrics?
        var fetchError: Error?
        
        Task {
            do {
                metrics = try await SystemMonitor.shared.getMetrics()
            } catch {
                fetchError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = fetchError {
            print("Error fetching metrics: \(error)")
            return
        }
        
        guard let m = metrics else {
            print("Error: Unable to fetch system metrics")
            return
        }
        
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
            print("  Memory:  \(String(format: "%.2f", Double(m.memoryUsed) / 1_073_741_824)) / \(String(format: "%.2f", Double(m.memoryTotal) / 1_073_741_824)) GB (\(String(format: "%.1f", m.memoryUsage * 100))%)")
            print("  Disk:    \(String(format: "%.2f", Double(m.diskUsed) / 1_073_741_824)) / \(String(format: "%.2f", Double(m.diskTotal) / 1_073_741_824)) GB (\(String(format: "%.1f", m.diskUsage * 100))%)")
            print("  Battery: \(String(format: "%.0f", m.batteryLevel))%")
        }
    }
}

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uninstall applications completely"
    )
    
    @Argument(help: "Application name to uninstall (partial match supported)")
    var appName: String?
    
    @Flag(name: .long, help: "List all installed applications")
    var list = false
    
    @Flag(name: .long, help: "Show residual files without uninstalling")
    var scan = false
    
    @Flag(name: .long, help: "Output as JSON")
    var json = false
    
    mutating func run() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var apps: [UninstallEngine.InstalledApp] = []
        var scanError: Error?
        
        print("🔍 Scanning installed applications...")
        
        Task {
            do {
                apps = try await UninstallEngine.shared.scanInstalledApps()
            } catch {
                scanError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = scanError {
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
            $0.name.lowercased().contains(name.lowercased()) ||
            $0.bundleID.lowercased().contains(name.lowercased())
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
           let str = String(data: data, encoding: .utf8) {
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
