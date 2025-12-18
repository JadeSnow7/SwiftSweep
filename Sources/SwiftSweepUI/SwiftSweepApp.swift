import SwiftUI

@main
struct SwiftSweepApp: App {
  init() {
    // Ensure the app appears in the Dock and has a UI
    NSApplication.shared.setActivationPolicy(.regular)

    DispatchQueue.main.async {
      NSApplication.shared.activate(ignoringOtherApps: true)
      NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .frame(minWidth: 900, minHeight: 700)
    }
    .windowResizability(.contentSize)
    .commands {
      SidebarCommands()

      CommandGroup(replacing: .appInfo) {
        Button("About SwiftSweep") {
          // TODO: Show about dialog
        }
      }
    }
  }
}

struct ContentView: View {
  @State private var selection: NavigationItem? = .status
  @StateObject private var navigationState = NavigationState.shared
  @State private var uninstallTargetURL: URL?

  enum NavigationItem: String, Hashable {
    case status
    case insights
    case clean
    case uninstall
    case optimize
    case analyze
    case applications
    #if !SWIFTSWEEP_MAS
      case packages
    #endif
    case settings
  }

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        Section(L10n.Nav.system.localized) {
          NavigationLink(value: NavigationItem.status) {
            Label(L10n.Nav.status.localized, systemImage: "chart.bar.fill")
          }
          NavigationLink(value: NavigationItem.insights) {
            Label("Insights", systemImage: "lightbulb.fill")
          }
        }

        Section(L10n.Nav.maintenance.localized) {
          NavigationLink(value: NavigationItem.clean) {
            Label(L10n.Nav.clean.localized, systemImage: "sparkles")
          }
          NavigationLink(value: NavigationItem.uninstall) {
            Label(L10n.Nav.uninstall.localized, systemImage: "xmark.bin.fill")
          }
          NavigationLink(value: NavigationItem.optimize) {
            Label(L10n.Nav.optimize.localized, systemImage: "bolt.fill")
          }
        }

        Section(L10n.Nav.tools.localized) {
          NavigationLink(value: NavigationItem.analyze) {
            Label(L10n.Nav.analyze.localized, systemImage: "magnifyingglass")
          }
          NavigationLink(value: NavigationItem.applications) {
            Label(L10n.Nav.applications.localized, systemImage: "square.grid.2x2")
          }
          #if !SWIFTSWEEP_MAS
            NavigationLink(value: NavigationItem.packages) {
              Label(L10n.Nav.packages.localized, systemImage: "shippingbox")
            }
          #endif
        }

        Section(L10n.Nav.settings.localized) {
          NavigationLink(value: NavigationItem.settings) {
            Label(L10n.Nav.settings.localized, systemImage: "gear")
          }
        }
      }
      .navigationTitle("SwiftSweep")
      .listStyle(SidebarListStyle())
    } detail: {
      Group {
        switch selection {
        case .status:
          StatusView()
        case .insights:
          InsightsView()
        case .clean:
          CleanView()
        case .uninstall:
          UninstallView(preselectedAppURL: uninstallTargetURL)
            .onDisappear {
              uninstallTargetURL = nil
            }
        case .optimize:
          OptimizeView()
        case .analyze:
          AnalyzeView()
        case .applications:
          MainApplicationsView()
        #if !SWIFTSWEEP_MAS
          case .packages:
            if #available(macOS 13.0, *) {
              PackageFinderView()
            } else {
              Text("Package Finder requires macOS 13.0 or later")
            }
        #endif
        case .settings:
          SettingsView()
        case .none:
          Text("Select an option")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onChange(of: navigationState.uninstallAppURL) { newURL in
      if let url = newURL {
        uninstallTargetURL = url
        selection = .uninstall
        navigationState.clearUninstallRequest()
      }
    }
  }
}

#Preview {
  ContentView()
}
