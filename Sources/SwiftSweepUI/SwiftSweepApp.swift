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

/// Custom NavigationLink wrapper with hover animation and selection transition for sidebar
struct SidebarNavLink<Value: Hashable>: View {
  let value: Value
  let title: String
  let icon: String

  @State private var isHovered = false
  @State private var isPressed = false
  @Environment(\.motionConfig) private var motion

  var body: some View {
    NavigationLink(value: value) {
      Label(title, systemImage: icon)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(SidebarButtonStyle(isHovered: isHovered, isPressed: isPressed, motion: motion))
    .onHover { isHovered = $0 }
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          if !isPressed { isPressed = true }
        }
        .onEnded { _ in
          isPressed = false
        }
    )
  }
}

/// Custom button style for sidebar items with hover → press → select transitions
struct SidebarButtonStyle: ButtonStyle {
  let isHovered: Bool
  let isPressed: Bool
  let motion: MotionConfig

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(backgroundView)
      .scaleEffect(scaleValue)
      .animation(
        motion.reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.75),
        value: isHovered
      )
      .animation(
        motion.reduceMotion ? nil : .spring(response: 0.15, dampingFraction: 0.8),
        value: isPressed
      )
  }

  private var backgroundView: some View {
    ZStack {
      // Hover shadow layer
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.accentColor.opacity(hoverOpacity))
        .shadow(
          color: Color.black.opacity(shadowOpacity),
          radius: shadowRadius,
          y: shadowY
        )

      // Press/selection transition layer
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.accentColor.opacity(borderOpacity), lineWidth: borderWidth)
    }
  }

  // MARK: - Computed Animation Values

  private var hoverOpacity: Double {
    if isPressed { return 0.15 }
    if isHovered { return 0.08 }
    return 0
  }

  private var shadowOpacity: Double {
    if isPressed { return 0.02 }
    if isHovered { return 0.08 }
    return 0
  }

  private var shadowRadius: CGFloat {
    if isPressed { return 1 }
    if isHovered { return 4 }
    return 0
  }

  private var shadowY: CGFloat {
    if isPressed { return 0 }
    if isHovered { return 2 }
    return 0
  }

  private var borderOpacity: Double {
    if isPressed { return 0.6 }
    return 0
  }

  private var borderWidth: CGFloat {
    isPressed ? 2 : 0
  }

  private var scaleValue: CGFloat {
    if isPressed && !motion.reduceMotion { return 0.98 }
    if isHovered && !motion.reduceMotion { return 1.02 }
    return 1.0
  }
}

#Preview {
  ContentView()
}
