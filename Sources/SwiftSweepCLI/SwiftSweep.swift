import Foundation
import ArgumentParser
import SwiftSweepCore

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
        abstract: "Analyze disk usage and show large files"
    )
    
    @Argument(help: "Path to analyze (default: home directory)")
    var path: String?
    
    @Option(name: .long, help: "Number of largest files to show")
    var top: Int = 10
    
    @Flag(name: .long, help: "Output as JSON")
    var json = false
    
    mutating func run() throws {
        let targetPath = path ?? NSHomeDirectory()
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: targetPath) else {
            print("❌ Path does not exist: \(targetPath)")
            return
        }
        
        print("🔍 Analyzing: \(targetPath)")
        print("   This may take a while for large directories...\n")
        
        var allFiles: [(path: String, size: Int64)] = []
        var totalSize: Int64 = 0
        var fileCount = 0
        var dirCount = 0
        
        if let enumerator = fileManager.enumerator(atPath: targetPath) {
            for case let file as String in enumerator {
                let fullPath = targetPath + "/" + file
                
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    if isDir.boolValue {
                        dirCount += 1
                    } else {
                        fileCount += 1
                        if let attrs = try? fileManager.attributesOfItem(atPath: fullPath) {
                            let size = attrs[.size] as? Int64 ?? 0
                            totalSize += size
                            allFiles.append((fullPath, size))
                        }
                    }
                }
            }
        }
        
        // Sort by size descending
        let topFiles = allFiles.sorted { $0.size > $1.size }.prefix(top)
        
        if json {
            var items: [[String: Any]] = []
            for file in topFiles {
                items.append([
                    "path": file.path,
                    "size": file.size,
                    "size_human": formatBytes(file.size)
                ])
            }
            
            let output: [String: Any] = [
                "path": targetPath,
                "total_size": totalSize,
                "total_size_human": formatBytes(totalSize),
                "file_count": fileCount,
                "dir_count": dirCount,
                "top_files": items
            ]
            
            if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("📊 Summary:")
            print("   Total Size:   \(formatBytes(totalSize))")
            print("   Files:        \(fileCount)")
            print("   Directories:  \(dirCount)")
            print("")
            print("📁 Top \(top) Largest Files:")
            print("")
            
            for (index, file) in topFiles.enumerated() {
                let relativePath = file.path.replacingOccurrences(of: targetPath + "/", with: "")
                print("  \(index + 1). \(formatBytes(file.size).padding(toLength: 12, withPad: " ", startingAt: 0)) \(relativePath)")
            }
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
    
    mutating func run() throws {
        print("Application uninstall not yet implemented in Swift CLI")
    }
}
