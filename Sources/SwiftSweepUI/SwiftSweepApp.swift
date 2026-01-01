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
    case packages
    case ghostBuster
    case galaxy
    case snapshot
    case mediaAnalyzer
    case ioAnalyzer
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

        Section(L10n.Nav.appManagement.localized) {
          NavigationLink(value: NavigationItem.clean) {
            Label(L10n.Nav.clean.localized, systemImage: "sparkles")
          }
          NavigationLink(value: NavigationItem.uninstall) {
            Label(L10n.Nav.uninstall.localized, systemImage: "xmark.bin.fill")
          }
          NavigationLink(value: NavigationItem.applications) {
            Label(L10n.Nav.applications.localized, systemImage: "square.grid.2x2")
          }
          NavigationLink(value: NavigationItem.optimize) {
            Label(L10n.Nav.optimize.localized, systemImage: "bolt.fill")
          }
          NavigationLink(value: NavigationItem.ghostBuster) {
            Label("Ghost Buster", systemImage: "figure.wave")
          }
        }

        Section(L10n.Nav.media.localized) {
          NavigationLink(value: NavigationItem.mediaAnalyzer) {
            Label("Media Analyzer", systemImage: "photo.stack")
          }
          NavigationLink(value: NavigationItem.analyze) {
            Label(L10n.Nav.analyze.localized, systemImage: "magnifyingglass")
          }
          NavigationLink(value: NavigationItem.snapshot) {
            Label("Time Machine", systemImage: "camera.on.rectangle")
          }
        }

        Section(L10n.Nav.developer.localized) {
          NavigationLink(value: NavigationItem.packages) {
            Label(L10n.Nav.packages.localized, systemImage: "shippingbox")
          }
          NavigationLink(value: NavigationItem.ioAnalyzer) {
            Label("I/O Analyzer", systemImage: "chart.line.uptrend.xyaxis")
          }
          NavigationLink(value: NavigationItem.galaxy) {
            Label("Galaxy", systemImage: "circle.hexagongrid")
          }
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
        case .packages:
          if #available(macOS 13.0, *) {
            PackageFinderView()
          } else {
            Text("Package Finder requires macOS 13.0 or later")
          }
        case .ghostBuster:
          if #available(macOS 13.0, *) {
            GhostBusterView()
          } else {
            Text("Ghost Buster requires macOS 13.0 or later")
          }
        case .galaxy:
          if #available(macOS 13.0, *) {
            GalaxyView()
          } else {
            Text("Galaxy requires macOS 13.0 or later")
          }
        case .snapshot:
          if #available(macOS 13.0, *) {
            SnapshotView()
          } else {
            Text("Time Machine requires macOS 13.0 or later")
          }
        case .mediaAnalyzer:
          MediaAnalyzerView()
        case .ioAnalyzer:
          IOAnalyzerView()
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
