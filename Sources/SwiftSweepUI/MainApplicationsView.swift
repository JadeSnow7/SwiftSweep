import SwiftUI
#if canImport(SwiftSweepCore)
#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif
#endif
import AppInventoryUI

/// Shared navigation state for passing data between views
@MainActor
final class NavigationState: ObservableObject {
    struct UninstallRequest: Equatable {
        let id: UUID
        let appURL: URL?
    }

    @Published var uninstallRequest: UninstallRequest?
    
    static let shared = NavigationState()
    
    private init() {}
    
    func requestUninstall(appURL: URL?) {
        uninstallRequest = UninstallRequest(id: UUID(), appURL: appURL)
    }
    
    func clearUninstallRequest() {
        uninstallRequest = nil
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigationState.requestUninstall(appURL: nil)
                } label: {
                    Label(L10n.Nav.uninstall.localized, systemImage: "xmark.bin.fill")
                }
                .help(L10n.Nav.uninstall.localized)
            }
        }
    }
}
