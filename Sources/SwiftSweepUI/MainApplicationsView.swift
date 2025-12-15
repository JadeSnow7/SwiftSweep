import SwiftUI
import SwiftSweepCore
import AppInventoryUI

/// Shared navigation state for passing data between views
@MainActor
final class NavigationState: ObservableObject {
    @Published var uninstallAppURL: URL?
    
    static let shared = NavigationState()
    
    private init() {}
    
    func requestUninstall(appURL: URL) {
        uninstallAppURL = appURL
    }
    
    func clearUninstallRequest() {
        uninstallAppURL = nil
    }
}

/// Applications View wrapper for SwiftSweep Main app.
/// This bridges the shared ApplicationsView to the Main app's UninstallEngine.
struct MainApplicationsView: View {
    @StateObject private var navigationState = NavigationState.shared
    
    var body: some View {
        ApplicationsView(
            defaults: UserDefaults.standard,
            onUninstallRequested: { app in
                // Request navigation to UninstallView with this app
                NavigationState.shared.requestUninstall(appURL: app.url)
            }
        )
        .onChange(of: navigationState.uninstallAppURL) { newURL in
            // Parent ContentView will observe this and navigate
        }
    }
}
