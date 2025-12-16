import Foundation
import SwiftUI

/// SwiftSweep 系统优化引擎
public final class OptimizationEngine {
    public static let shared = OptimizationEngine()
    
    private init() {}
    
    public struct OptimizationTask: Identifiable {
        public let id = UUID()
        public let title: String
        public let description: String
        public let icon: String
        public let color: Color
        public let taskType: TaskType
        public let requiresPrivilege: Bool
        public var isRunning: Bool = false
        public var lastResult: Bool? = nil
        
        public enum TaskType: Sendable {
            case flushDNS
            case rebuildSpotlight
            case clearMemory
            case resetDock
            case resetFinder
            case clearFontCache
        }
        
        public init(title: String, description: String, icon: String, color: Color, taskType: TaskType, requiresPrivilege: Bool) {
            self.title = title
            self.description = description
            self.icon = icon
            self.color = color
            self.taskType = taskType
            self.requiresPrivilege = requiresPrivilege
        }
    }
    
    public let availableTasks: [OptimizationTask] = [
        OptimizationTask(
            title: "Flush DNS Cache",
            description: "Clear DNS resolver cache to fix network issues",
            icon: "network",
            color: .blue,
            taskType: .flushDNS,
            requiresPrivilege: true
        ),
        OptimizationTask(
            title: "Rebuild Spotlight",
            description: "Rebuild search index if Spotlight is slow",
            icon: "magnifyingglass",
            color: .purple,
            taskType: .rebuildSpotlight,
            requiresPrivilege: true
        ),
        OptimizationTask(
            title: "Clear Memory",
            description: "Purge inactive memory to free up RAM",
            icon: "memorychip",
            color: .green,
            taskType: .clearMemory,
            requiresPrivilege: true
        ),
        OptimizationTask(
            title: "Reset Dock",
            description: "Restart Dock to fix UI glitches",
            icon: "dock.rectangle",
            color: .orange,
            taskType: .resetDock,
            requiresPrivilege: false
        ),
        OptimizationTask(
            title: "Reset Finder",
            description: "Restart Finder to refresh file system",
            icon: "folder",
            color: .cyan,
            taskType: .resetFinder,
            requiresPrivilege: false
        ),
        OptimizationTask(
            title: "Clear Font Cache",
            description: "Remove cached fonts to fix font issues",
            icon: "textformat",
            color: .pink,
            taskType: .clearFontCache,
            requiresPrivilege: true
        ),
    ]
    
    /// 运行优化任务
    public func run(_ task: OptimizationTask) async -> Bool {
        if task.requiresPrivilege {
            return await runPrivileged(task: task)
        } else {
            return await runStandard(task: task)
        }
    }
    
    private func runStandard(task: OptimizationTask) async -> Bool {
        let taskType = task.taskType
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                
                switch taskType {
                case .resetDock:
                    process.arguments = ["Dock"]
                case .resetFinder:
                    process.arguments = ["Finder"]
                default:
                    continuation.resume(returning: false)
                    return
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    private func runPrivileged(task: OptimizationTask) async -> Bool {
        guard #available(macOS 13.0, *) else {
            // Fallback to AppleScript for older systems
            return await runPrivilegedLegacy(task: task)
        }
        
        let client = HelperClient.shared
        
        // Check if helper is installed
        let status = client.checkStatus()
        if status != .enabled {
            // Fall back to legacy method if helper not installed
            return await runPrivilegedLegacy(task: task)
        }
        
        do {
            switch task.taskType {
            case .flushDNS:
                _ = try await client.flushDNS()
            case .rebuildSpotlight:
                _ = try await client.rebuildSpotlight()
            case .clearMemory:
                _ = try await client.purgeMemory()
            case .clearFontCache:
                _ = try await client.clearFontCache()
            default:
                return false
            }
            return true
        } catch {
            print("Helper error: \(error.localizedDescription)")
            // Fallback to legacy on error
            return await runPrivilegedLegacy(task: task)
        }
    }
    
    private func runPrivilegedLegacy(task: OptimizationTask) async -> Bool {
        let taskType = task.taskType
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let command: String
                switch taskType {
                case .flushDNS:
                    command = "dscacheutil -flushcache && killall -HUP mDNSResponder"
                case .rebuildSpotlight:
                    command = "mdutil -E /"
                case .clearMemory:
                    command = "purge"
                case .clearFontCache:
                    command = "atsutil databases -remove"
                default:
                    continuation.resume(returning: false)
                    return
                }
                
                let script = """
                do shell script "\(command)" with administrator privileges
                """
                
                var error: NSDictionary?
                if let appleScript = NSAppleScript(source: script) {
                    _ = appleScript.executeAndReturnError(&error)
                    continuation.resume(returning: error == nil)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
