import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

#if canImport(SwiftSweepCapCutPlugin)
  import SwiftSweepCapCutPlugin
#endif

@main
struct SwiftSweepApp: App {
  init() {
    // Register Plugins
    PluginManager.shared.register(CapCutPlugin())

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
        .withMotionConfig()  // Enable global motion configuration
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
  @AppStorage("PluginEnabled_com.swiftsweep.capcut") private var isCapCutEnabled = false

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
    case capCut
    case settings
  }

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        Section(L10n.Nav.system.localized) {
          SidebarNavLink(
            value: NavigationItem.status, title: L10n.Nav.status.localized, icon: "chart.bar.fill")
          SidebarNavLink(value: NavigationItem.insights, title: "Insights", icon: "lightbulb.fill")
        }

        Section(L10n.Nav.maintenance.localized) {
          SidebarNavLink(
            value: NavigationItem.clean, title: L10n.Nav.clean.localized, icon: "sparkles")
          SidebarNavLink(
            value: NavigationItem.optimize, title: L10n.Nav.optimize.localized, icon: "bolt.fill")
        }

        Section(L10n.Nav.appManagement.localized) {
          SidebarNavLink(
            value: NavigationItem.applications, title: L10n.Nav.applications.localized,
            icon: "square.grid.2x2")
        }

        Section(L10n.Nav.media.localized) {
          SidebarNavLink(
            value: NavigationItem.analyze, title: L10n.Nav.analyze.localized,
            icon: "magnifyingglass")
          SidebarNavLink(
            value: NavigationItem.mediaAnalyzer, title: "Media Analyzer", icon: "photo.stack")
          SidebarNavLink(
            value: NavigationItem.snapshot, title: "Time Machine", icon: "camera.on.rectangle")
        }

        Section(L10n.Nav.developer.localized) {
          SidebarNavLink(
            value: NavigationItem.packages, title: L10n.Nav.packages.localized, icon: "shippingbox")
          SidebarNavLink(
            value: NavigationItem.ghostBuster, title: "Ghost Buster", icon: "figure.wave")
          SidebarNavLink(value: NavigationItem.galaxy, title: "Galaxy", icon: "circle.hexagongrid")
          SidebarNavLink(
            value: NavigationItem.ioAnalyzer, title: "I/O Analyzer",
            icon: "chart.line.uptrend.xyaxis")
          if isCapCutEnabled {
            SidebarNavLink(
              value: NavigationItem.capCut, title: "CapCut Cleaner", icon: "video.badge.plus")
          }
        }

        Section(L10n.Nav.settings.localized) {
          SidebarNavLink(
            value: NavigationItem.settings, title: L10n.Nav.settings.localized, icon: "gear")
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
        case .capCut:
          Text("CapCut Cleaner Plugin")
        case .settings:
          SettingsView()
        case .none:
          Text("Select an option")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onChange(of: navigationState.uninstallRequest) { request in
      guard let request else { return }
      uninstallTargetURL = request.appURL
      selection = .uninstall
      navigationState.clearUninstallRequest()
    }
  }
}

// MARK: - Sidebar Navigation Link with Hover Effect

/// Custom NavigationLink wrapper with hover animation for sidebar
/// Simplified version without DragGesture to avoid lag
struct SidebarNavLink<Value: Hashable>: View {
  let value: Value
  let title: String
  let icon: String

  @State private var isHovered = false
  @Environment(\.motionConfig) private var motion

  var body: some View {
    NavigationLink(value: value) {
      HStack(spacing: 8) {
        Image(systemName: icon)
          .foregroundColor(isHovered ? .accentColor : .secondary)
          .font(.body)
        Text(title)
          .foregroundColor(.primary)
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
      )
      .scaleEffect(isHovered && !motion.reduceMotion ? 1.01 : 1.0)
    }
    .buttonStyle(.plain)
    .animation(
      motion.reduceMotion ? nil : .easeOut(duration: 0.15),
      value: isHovered
    )
    .onHover { isHovered = $0 }
  }
}

#Preview {
  ContentView()
}
