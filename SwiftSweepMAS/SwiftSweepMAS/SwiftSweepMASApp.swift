import SwiftUI
import UserNotifications

@main
struct SwiftSweepMASApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task { @MainActor in
                        handleDeepLink(url)
                    }
                }
        }
    }
    
    @MainActor
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "swiftsweepmas",
              url.host == "analyze",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let pathItem = components.queryItems?.first(where: { $0.name == "path" }),
              let rawPath = pathItem.value else {
            return
        }
        
        // Normalize path: resolve symlinks and standardize
        let normalizedURL = URL(fileURLWithPath: rawPath)
            .resolvingSymlinksInPath()
            .standardized
        let path = normalizedURL.path
        
        // Validate against normalized authorized paths
        let authorizedPaths = BookmarkManager.shared.resolveAuthorizedDirectories()
            .map { $0.resolvingSymlinksInPath().standardized.path }
        
        let isAuthorized = authorizedPaths.contains { authorizedPath in
            path.hasPrefix(authorizedPath)
        }
        
        guard isAuthorized else {
            // Path not in authorized directories
            print("Deep link path not authorized: \(path)")
            return
        }
        
        // Reject system paths
        let forbiddenPrefixes = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private/var"]
        for prefix in forbiddenPrefixes {
            if path.hasPrefix(prefix) {
                print("Deep link path is system path: \(path)")
                return
            }
        }
        
        // Navigate to analysis
        NavigationManager.shared.navigateToAnalysis(path: path)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    
    // Handle notification click
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let path = response.notification.request.content.userInfo["path"] as? String {
            Task { @MainActor in
                NavigationManager.shared.navigateToAnalysis(path: path)
            }
        }
        completionHandler()
    }
    
    // Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Navigation Manager

@MainActor
class NavigationManager: ObservableObject {
    static let shared = NavigationManager()
    
    @Published var currentAnalysisPath: String?
    @Published var showingAnalysis = false
    
    private init() {}
    
    func navigateToAnalysis(path: String) {
        currentAnalysisPath = path
        showingAnalysis = true
    }
}
