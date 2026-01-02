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
            shortTitle: "Apps", icon: "square.grid.2x2")
        }

        Section(L10n.Nav.media.localized) {
          SidebarNavLink(
            value: NavigationItem.analyze, title: L10n.Nav.analyze.localized,
            icon: "magnifyingglass")
          SidebarNavLink(
            value: NavigationItem.mediaAnalyzer, title: "Media Analyzer",
            shortTitle: "Media", icon: "photo.stack")
          SidebarNavLink(
            value: NavigationItem.snapshot, title: "Time Machine",
            shortTitle: "Snapshot", icon: "camera.on.rectangle")
        }

        Section(L10n.Nav.developer.localized) {
          SidebarNavLink(
            value: NavigationItem.packages, title: L10n.Nav.packages.localized,
            shortTitle: "Pkgs", icon: "shippingbox")
          SidebarNavLink(
            value: NavigationItem.ghostBuster, title: "Ghost Buster",
            shortTitle: "Ghost", icon: "figure.wave")
          SidebarNavLink(value: NavigationItem.galaxy, title: "Galaxy", icon: "circle.hexagongrid")
          SidebarNavLink(
            value: NavigationItem.ioAnalyzer, title: "I/O Analyzer",
            shortTitle: "I/O", icon: "chart.line.uptrend.xyaxis")
          if isCapCutEnabled {
            SidebarNavLink(
              value: NavigationItem.capCut, title: "CapCut Cleaner",
              shortTitle: "CapCut", icon: "video.badge.plus")
          }
        }

        Section(L10n.Nav.settings.localized) {
          SidebarNavLink(
            value: NavigationItem.settings, title: L10n.Nav.settings.localized, icon: "gear")
        }
      }
      .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
      .navigationTitle("SwiftSweep")
      .listStyle(SidebarListStyle())
      .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
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
/// Supports short/long text with ViewThatFits for adaptive display
struct SidebarNavLink<Value: Hashable>: View {
  let value: Value
  let title: String
  let shortTitle: String?
  let icon: String

  @State private var isHovered = false
  @Environment(\.motionConfig) private var motion

  init(value: Value, title: String, shortTitle: String? = nil, icon: String) {
    self.value = value
    self.title = title
    self.shortTitle = shortTitle
    self.icon = icon
  }

  var body: some View {
    NavigationLink(value: value) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .foregroundColor(isHovered ? .accentColor : .secondary)
          .font(.body)
          .frame(width: 18)

        // ViewThatFits: try full title, fallback to short title
        ViewThatFits(in: .horizontal) {
          Text(title)
            .lineLimit(1)

          if let short = shortTitle {
            Text(short)
              .lineLimit(1)
          }
        }
        .foregroundColor(.primary)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
      )
      .scaleEffect(isHovered && !motion.reduceMotion ? 1.01 : 1.0)
    }
    .buttonStyle(.plain)
    .help(title)  // Full title on hover tooltip
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
