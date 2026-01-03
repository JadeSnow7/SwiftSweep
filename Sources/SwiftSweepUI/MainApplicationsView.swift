import AppInventoryUI
import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

/// Applications View wrapper for SwiftSweep Main app.
/// This bridges the shared ApplicationsView to the Main app's UninstallEngine.
struct MainApplicationsView: View {
  @EnvironmentObject private var store: AppStore

  var body: some View {
    ApplicationsView(
      defaults: UserDefaults.standard,
      onUninstallRequested: { app in
        // Request navigation to UninstallView with this app via AppStore
        store.dispatch(.navigation(.requestUninstall(app.url)))
      }
    )
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          store.dispatch(.navigation(.requestUninstall(nil)))
        } label: {
          Label(L10n.Nav.uninstall.localized, systemImage: "xmark.bin.fill")
        }
        .help(L10n.Nav.uninstall.localized)
      }
    }
  }
}
