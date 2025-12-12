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
        public let color: Color // 注意: Core 引用 SwiftUI Color 可能需要考虑分离，但为了简单起见暂且保留
        public let command: String
        public let requiresPrivilege: Bool
        public var isRunning: Bool = false
        public var lastResult: Bool? = nil
        
        public init(title: String, description: String, icon: String, color: Color, command: String, requiresPrivilege: Bool) {
            self.title = title
            self.description = description
            self.icon = icon
            self.color = color
            self.command = command
            self.requiresPrivilege = requiresPrivilege
        }
    }
    
    public let availableTasks: [OptimizationTask] = [
        OptimizationTask(
            title: "Flush DNS Cache",
            description: "Clear DNS resolver cache to fix network issues",
            icon: "network",
            color: .blue,
            command: "dscacheutil -flushcache && killall -HUP mDNSResponder",
            requiresPrivilege: true
        ),
        OptimizationTask(
            title: "Rebuild Spotlight",
            description: "Rebuild search index if Spotlight is slow",
            icon: "magnifyingglass",
            color: .purple,
            command: "mdutil -E /",
            requiresPrivilege: true
        ),
        OptimizationTask(
            title: "Clear Memory",
            description: "Purge inactive memory to free up RAM",
            icon: "memorychip",
            color: .green,
            command: "purge",
            requiresPrivilege: true
        ),
        OptimizationTask(
            title: "Reset Dock",
            description: "Restart Dock to fix UI glitches",
            icon: "dock.rectangle",
            color: .orange,
            command: "killall Dock",
            requiresPrivilege: false
        ),
        OptimizationTask(
            title: "Reset Finder",
            description: "Restart Finder to refresh file system",
            icon: "folder",
            color: .cyan,
            command: "killall Finder",
            requiresPrivilege: false
        ),
        OptimizationTask(
            title: "Clear Font Cache",
            description: "Remove cached fonts to fix font issues",
            icon: "textformat",
            color: .pink,
            command: "atsutil databases -remove",
            requiresPrivilege: true
        ),
    ]
    
    /// 运行优化任务
    public func run(_ task: OptimizationTask) async -> Bool {
        if task.requiresPrivilege {
            return await runPrivileged(command: task.command)
        } else {
            return await runStandard(command: task.command)
        }
    }
    
    private func runStandard(command: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]
                
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
    
    private func runPrivileged(command: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
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
