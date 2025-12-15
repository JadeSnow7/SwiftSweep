import SwiftUI
import SwiftSweepCore

struct UninstallView: View {
    @StateObject private var viewModel = UninstallViewModel()
    @State private var searchText = ""
    
    /// Optional pre-selected app URL passed from Applications view
    var preselectedAppURL: URL?
    
    init(preselectedAppURL: URL? = nil) {
        self.preselectedAppURL = preselectedAppURL
    }
    
    var filteredApps: [UninstallEngine.InstalledApp] {
        if searchText.isEmpty {
            return viewModel.apps
        }
        return viewModel.apps.filter {
            $0.name.lowercased().contains(searchText.lowercased()) ||
            $0.bundleID.lowercased().contains(searchText.lowercased())
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("App Uninstaller")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Remove apps and their residual files")
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                if viewModel.isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: { Task { await viewModel.scanApps() }}) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            
            Divider()
                .padding(.top)
            
            if viewModel.apps.isEmpty && !viewModel.isScanning {
                VStack {
                    Spacer()
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No apps scanned yet")
                        .foregroundColor(.secondary)
                    Button("Scan Applications") {
                        Task { await viewModel.scanApps() }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // App List
                List(filteredApps, selection: $viewModel.selectedApp) { app in
                    AppRow(app: app, isSelected: viewModel.selectedApp?.id == app.id)
                        .tag(app)
                }
                .listStyle(.inset)
            }
            
            // Detail Panel
            if let selected = viewModel.selectedApp {
                Divider()
                AppDetailPanel(app: selected, residuals: viewModel.residualFiles, viewModel: viewModel)
            }
        }
        .onAppear {
            Task {
                if viewModel.apps.isEmpty {
                    await viewModel.scanApps()
                }
                // If pre-selected app, find and select it
                if let url = preselectedAppURL {
                    viewModel.selectApp(byURL: url)
                }
            }
        }
    }
}

struct AppRow: View {
    let app: UninstallEngine.InstalledApp
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // App Icon placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "app.fill")
                        .foregroundColor(.blue)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name.replacingOccurrences(of: ".app", with: ""))
                    .fontWeight(.medium)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(formatBytes(app.size))
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb > 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

struct AppDetailPanel: View {
    let app: UninstallEngine.InstalledApp
    let residuals: [UninstallEngine.ResidualFile]
    @ObservedObject var viewModel: UninstallViewModel
    
    var totalSize: Int64 {
        app.size + residuals.reduce(0) { $0 + $1.size }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(app.name.replacingOccurrences(of: ".app", with: ""))
                        .font(.headline)
                    Text("Total: \(formatBytes(totalSize))")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if viewModel.isLoadingResiduals {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                Button(action: {}) {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(true) // Requires privileged helper
            }
            
            if !residuals.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ResidualBadge(label: "App", size: app.size, color: .blue)
                        
                        ForEach(Array(Dictionary(grouping: residuals) { $0.type }.sorted(by: { $0.key.rawValue < $1.key.rawValue })), id: \.key) { type, files in
                            let size = files.reduce(0) { $0 + $1.size }
                            ResidualBadge(label: type.rawValue, size: size, color: colorForType(type))
                        }
                    }
                }
            }
            
            Text("⚠️ Uninstallation requires privileged helper (not yet implemented)")
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    func colorForType(_ type: UninstallEngine.ResidualType) -> Color {
        switch type {
        case .cache: return .orange
        case .preferences: return .purple
        case .appSupport: return .green
        case .launchAgent: return .red
        case .container: return .cyan
        case .other: return .gray
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb > 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }
}

struct ResidualBadge: View {
    let label: String
    let size: Int64
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(formatBytes(size))
                .font(.caption)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb > 1024 {
            return String(format: "%.1f GB", mb / 1024)
        } else if mb > 1 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
    }
}

@MainActor
class UninstallViewModel: ObservableObject {
    @Published var apps: [UninstallEngine.InstalledApp] = []
    @Published var selectedApp: UninstallEngine.InstalledApp?
    @Published var residualFiles: [UninstallEngine.ResidualFile] = []
    @Published var isScanning = false
    @Published var isLoadingResiduals = false
    
    func scanApps() async {
        isScanning = true
        do {
            apps = try await UninstallEngine.shared.scanInstalledApps()
        } catch {
            print("Error scanning apps: \(error)")
        }
        isScanning = false
    }
    
    func loadResiduals(for app: UninstallEngine.InstalledApp) {
        isLoadingResiduals = true
        do {
            residualFiles = try UninstallEngine.shared.findResidualFiles(for: app)
        } catch {
            print("Error finding residuals: \(error)")
            residualFiles = []
        }
        isLoadingResiduals = false
    }
    
    /// Select an app by its path URL (for navigation from Applications view)
    func selectApp(byURL url: URL) {
        if let app = apps.first(where: { $0.path == url.path }) {
            selectedApp = app
            loadResiduals(for: app)
        } else {
            // App not in scanned list, create a temporary entry
            let fm = FileManager.default
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier ?? url.lastPathComponent
            let tempApp = UninstallEngine.InstalledApp(
                name: url.deletingPathExtension().lastPathComponent,
                bundleID: bundleID,
                path: url.path,
                size: size,
                lastUsed: nil
            )
            apps.insert(tempApp, at: 0)
            selectedApp = tempApp
            loadResiduals(for: tempApp)
        }
    }
}
