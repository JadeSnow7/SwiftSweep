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
    
    @Flag(name: .long, help: "Show whitelist management")
    var whitelist = false
    
    mutating func run() throws {
        if whitelist {
            print("Whitelist management not yet implemented")
            return
        }
        
        if dryRun {
            print("Running in dry-run mode (preview only)")
        }
        
        print("System cleanup not yet implemented in Swift CLI")
    }
}

struct Analyze: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Analyze disk usage and show large files"
    )
    
    mutating func run() throws {
        print("Disk analysis not yet implemented in Swift CLI")
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
