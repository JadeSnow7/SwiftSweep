import Cocoa
import UserNotifications

/// Presents analysis results - notification if possible, otherwise opens Host App
struct ResultPresenter {
    
    /// Show result - notification if authorized, otherwise open Host App
    @MainActor
    static func showResult(_ summary: AnalyzerEngine.QuickSummary, for path: String) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        if settings.authorizationStatus == .authorized {
            // Best case: show notification
            await postNotification(summary: summary, path: path)
        } else {
            // Fallback: open Host App directly (no blocking modal)
            openInHostApp(path: path)
        }
    }
    
    /// Post a notification with analysis summary
    private static func postNotification(summary: AnalyzerEngine.QuickSummary, path: String) async {
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        
        let content = UNMutableNotificationContent()
        content.title = "📊 \(folderName)"
        
        var bodyLines = [
            "Size: \(summary.totalSize)",
            "Files: \(summary.fileCount) | Folders: \(summary.dirCount)"
        ]
        
        if let largest = summary.largestItem {
            bodyLines.append("Largest: \(largest.name) (\(largest.size))")
        }
        
        if summary.wasLimited {
            bodyLines.append("⚠️ Partial result - open for full analysis")
        }
        
        content.body = bodyLines.joined(separator: "\n")
        content.userInfo = ["path": path]
        content.sound = nil  // Silent notification
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            NSLog("SwiftSweep: Failed to post notification - \(error.localizedDescription)")
            openInHostApp(path: path)
        }
    }
    
    /// Open Host App with path for detailed analysis
    static func openInHostApp(path: String) {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "swiftsweepmas://analyze?path=\(encoded)") else {
            NSLog("SwiftSweep: Failed to create deep link URL")
            return
        }
        
        NSWorkspace.shared.open(url)
    }
}
