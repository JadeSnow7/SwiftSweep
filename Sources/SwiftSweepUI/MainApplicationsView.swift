import SwiftUI
import SwiftSweepCore
import AppInventoryUI

/// Applications View wrapper for SwiftSweep Main app.
/// This bridges the shared ApplicationsView to the Main app's UninstallEngine.
struct MainApplicationsView: View {
    var body: some View {
        ApplicationsView(
            defaults: UserDefaults.standard,
            onUninstallRequested: { app in
                // Bridge to UninstallEngine
                Task { @MainActor in
                    await triggerUninstall(appURL: app.url)
                }
            }
        )
    }
    
    @MainActor
    private func triggerUninstall(appURL: URL) async {
        // Create an InstalledApp from the URL and scan for residuals
        // This is the bridge between AppInventory and UninstallEngine
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: appURL.path),
              let size = attributes[.size] as? Int64 else {
            return
        }
        
        let bundle = Bundle(url: appURL)
        let bundleID = bundle?.bundleIdentifier ?? appURL.lastPathComponent
        
        let installedApp = UninstallEngine.InstalledApp(
            name: appURL.deletingPathExtension().lastPathComponent,
            bundleID: bundleID,
            path: appURL.path,
            size: size,
            lastUsed: nil
        )
        
        // Find residuals and show in UI (This would typically navigate to UninstallView)
        do {
            let residuals = try UninstallEngine.shared.findResidualFiles(for: installedApp)
            // For now, just print - in a full implementation, this would navigate to the UninstallView
            print("Found \(residuals.count) residual files for \(installedApp.name)")
        } catch {
            print("Error finding residuals: \(error)")
        }
    }
}
