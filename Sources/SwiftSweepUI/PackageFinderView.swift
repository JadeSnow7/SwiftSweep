import SwiftUI
#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif

#if !SWIFTSWEEP_MAS

/// View for discovering installed packages from various package managers
@available(macOS 13.0, *)
public struct PackageFinderView: View {
    @StateObject private var viewModel = PackageFinderViewModel()
    @State private var searchText = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            if viewModel.isScanning && viewModel.results.isEmpty {
                loadingView
            } else if viewModel.results.isEmpty {
                emptyView
            } else {
                resultsList
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search packages")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.scan() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isScanning)
            }
        }
        .task {
            await viewModel.scan()
        }
        .navigationTitle("Packages")
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            if viewModel.isScanning {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Scanning...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                let totalPackages = viewModel.results.reduce(0) { $0 + $1.packages.count }
                Text("\(totalPackages) packages from \(viewModel.results.filter { if case .ok = $0.status { return true } else { return false } }.count) sources")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let lastScan = viewModel.lastScanTime {
                Text("Last scan: \(lastScan, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Scanning package managers...")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Checking Homebrew, npm, pip, gem...")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No package managers found")
                .font(.headline)
            Text("Install Homebrew, npm, pip, or gem to see packages here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Install Homebrew") {
                if let url = URL(string: "https://brew.sh") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Results List
    
    private var resultsList: some View {
        List {
            ForEach(viewModel.results, id: \.providerID) { result in
                providerSection(result)
            }
        }
        .listStyle(.inset)
    }
    
    @ViewBuilder
    private func providerSection(_ result: PackageScanResult) -> some View {
        Section {
            switch result.status {
            case .ok:
                let filtered = filteredPackages(result.packages)
                if filtered.isEmpty && !searchText.isEmpty {
                    Text("No matches")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(filtered) { package in
                        packageRow(package)
                    }
                }
            case .notInstalled:
                notInstalledRow(result)
            case .failed(let error):
                failedRow(error)
            }
        } header: {
            providerHeader(result)
        }
    }
    
    private func providerHeader(_ result: PackageScanResult) -> some View {
        HStack {
            Image(systemName: iconFor(result.providerID))
                .foregroundColor(.accentColor)
            Text(result.displayName)
            
            Spacer()
            
            if case .ok = result.status {
                Text("\(result.packages.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .quaternaryLabelColor))
                    .cornerRadius(4)
            }
            
            if result.scanDuration > 0 {
                Text(String(format: "%.1fs", result.scanDuration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func packageRow(_ package: Package) -> some View {
        HStack {
            Text(package.name)
                .fontWeight(.medium)
            Spacer()
            Text(package.version)
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .quaternaryLabelColor))
                .cornerRadius(4)
        }
        .contextMenu {
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(package.name, forType: .string)
            }
            Button("Copy Name and Version") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(package.name)@\(package.version)", forType: .string)
            }
        }
    }
    
    private func notInstalledRow(_ result: PackageScanResult) -> some View {
        HStack {
            Image(systemName: "xmark.circle")
                .foregroundColor(.secondary)
            Text("Not installed")
                .foregroundColor(.secondary)
            Spacer()
            if let url = installURL(for: result.providerID) {
                Button("Install Guide") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderless)
            }
        }
    }
    
    private func failedRow(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }
    
    // MARK: - Helpers
    
    private func filteredPackages(_ packages: [Package]) -> [Package] {
        guard !searchText.isEmpty else { return packages }
        let query = searchText.lowercased()
        return packages.filter {
            $0.name.lowercased().contains(query) ||
            $0.version.lowercased().contains(query)
        }
    }
    
    private func iconFor(_ providerID: String) -> String {
        switch providerID {
        case "homebrew_formula", "homebrew_cask": return "mug.fill"
        case "npm": return "shippingbox.fill"
        case "pip": return "cube.box.fill"
        case "gem": return "diamond.fill"
        default: return "shippingbox"
        }
    }
    
    private func installURL(for providerID: String) -> URL? {
        switch providerID {
        case "homebrew_formula", "homebrew_cask":
            return URL(string: "https://brew.sh")
        case "npm":
            return URL(string: "https://nodejs.org")
        case "pip":
            return URL(string: "https://www.python.org/downloads/")
        case "gem":
            return URL(string: "https://www.ruby-lang.org/en/downloads/")
        default:
            return nil
        }
    }
}

// MARK: - View Model

@available(macOS 13.0, *)
@MainActor
final class PackageFinderViewModel: ObservableObject {
    @Published var results: [PackageScanResult] = []
    @Published var isScanning = false
    @Published var lastScanTime: Date?
    
    private let scanner = PackageScanner.shared
    
    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        
        results = await scanner.scanAll()
        lastScanTime = Date()
    }
}

#endif
