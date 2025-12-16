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
        case clean
        case uninstall
        case optimize
        case analyze
        case applications
        case settings
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("System") {
                    NavigationLink(value: NavigationItem.status) {
                        Label("Status", systemImage: "chart.bar.fill")
                    }
                }
                
                Section("Maintenance") {
                    NavigationLink(value: NavigationItem.clean) {
                        Label("Clean", systemImage: "sparkles")
                    }
                    NavigationLink(value: NavigationItem.uninstall) {
                        Label("Uninstall", systemImage: "xmark.bin.fill")
                    }
                    NavigationLink(value: NavigationItem.optimize) {
                        Label("Optimize", systemImage: "bolt.fill")
                    }
                }
                
                Section("Tools") {
                    NavigationLink(value: NavigationItem.analyze) {
                        Label("Analyze", systemImage: "magnifyingglass")
                    }
                    NavigationLink(value: NavigationItem.applications) {
                        Label("Applications", systemImage: "square.grid.2x2")
                    }
                }
                
                Section("Settings") {
                    NavigationLink(value: NavigationItem.settings) {
                        Label("Settings", systemImage: "gear")
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
