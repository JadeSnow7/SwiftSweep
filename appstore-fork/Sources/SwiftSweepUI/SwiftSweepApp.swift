import SwiftUI
import SwiftSweepCore

@main
struct SwiftSweepApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        
        Settings {
            SettingsView()
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: SidebarItem = .status

    enum SidebarItem: String, CaseIterable, Identifiable {
        case status = "Status"
        case analyze = "Analyze"
        case settings = "Settings"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .status: return "gauge.with.dots.needle.bottom.50percent"
            case .analyze: return "chart.pie"
            case .settings: return "gear"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedTab) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selectedTab {
            case .status:
                StatusView()
            case .analyze:
                AnalyzeView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
