import SwiftUI
import AppKit
import AppInventoryLogic

/// Main Applications View, shared between MAS and Main apps.
public struct ApplicationsView: View {
    @StateObject private var viewModel: AppInventoryViewModel
    @State private var showingFileImporter = false
    @State private var showingCategorySheet = false
    @State private var newCategoryName = ""
    
    /// Action callback for Main app's "Uninstall" feature. Nil for MAS.
    public var onUninstallRequested: ((AppItem) -> Void)?
    
    public init(defaults: UserDefaults, onUninstallRequested: ((AppItem) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: AppInventoryViewModel(defaults: defaults))
        self.onUninstallRequested = onUninstallRequested
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Status Bar
            statusBar
            
            Divider()
            
            // Main Content
            if viewModel.apps.isEmpty {
                emptyStateView
            } else {
                appGrid
            }
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Filter", selection: $viewModel.selectedFilter) {
                    ForEach(AppInventoryViewModel.FilterType.allCases) { filter in
                        if filter == .unused && !viewModel.hasLastUsedData {
                            Text("\(filter.rawValue) (N/A)")
                                .tag(filter)
                                .foregroundColor(.secondary)
                        } else {
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                }
                .pickerStyle(.menu)
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCategorySheet = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Manage Categories")
            }
        }
        .sheet(isPresented: $showingCategorySheet) {
            CategoryManagementSheet(viewModel: viewModel)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleAuthorization(result: result)
        }
        .task {
            await viewModel.loadApps()
        }
        .navigationTitle("Applications")
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            stateIndicator
            
            Spacer()
            
            if viewModel.isAuthorized {
                switch viewModel.state {
                case .deepScanning(let current, let total):
                    Text("Scanning: \(current)/\(total)")
                        .font(.caption)
                    Button("Cancel") {
                        Task { await viewModel.cancelDeepScan() }
                    }
                    .buttonStyle(.borderless)
                default:
                    Button("Recalculate Sizes") {
                        Task { await viewModel.startDeepScan() }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button("Authorize /Applications") {
                    showingFileImporter = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    @ViewBuilder
    private var stateIndicator: some View {
        switch viewModel.state {
        case .idle, .loadingBaseline:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text("Loading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .baselineReady:
            Text("\(viewModel.apps.count) apps (estimated sizes)")
                .font(.caption)
                .foregroundColor(.secondary)
        case .authorizedReady:
            Text("\(viewModel.apps.count) apps (accurate sizes)")
                .font(.caption)
                .foregroundColor(.green)
        case .baselineUnavailableOrEmpty:
            Text("No apps found. Authorize /Applications to scan.")
                .font(.caption)
                .foregroundColor(.orange)
        case .deepScanning:
            ProgressView().scaleEffect(0.7)
        case .error(let msg):
            Text(msg)
                .font(.caption)
                .foregroundColor(.red)
        }
    }
    
    // MARK: - App Grid
    
    private var appGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                ForEach(viewModel.filteredApps) { app in
                    AppCell(
                        app: app,
                        assignments: viewModel.assignments,
                        categories: viewModel.categories,
                        onAssign: { categoryID in
                            viewModel.assignApp(app.id, to: categoryID)
                        },
                        onUninstall: onUninstallRequested != nil ? {
                            onUninstallRequested?(app)
                        } : nil
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "app.dashed")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            switch viewModel.state {
            case .loadingBaseline:
                Text("Loading applications...")
                    .font(.headline)
            case .baselineUnavailableOrEmpty:
                Text("Spotlight index unavailable")
                    .font(.headline)
                Text("Authorize /Applications to scan directly and get accurate sizes.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Authorize /Applications") {
                    showingFileImporter = true
                }
                .buttonStyle(.borderedProminent)
            default:
                Text("No applications found")
                    .font(.headline)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // MARK: - Helpers
    
    private func handleAuthorization(result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first else {
            return
        }
        
        if !viewModel.authorize(url: url) {
            // Show error - path was not /Applications
            // In a real app, you might show an alert here
        } else {
            // If we had no apps, trigger a deep scan to list them
            if viewModel.apps.isEmpty {
                Task { await viewModel.startDeepScan() }
            }
        }
    }
}

// MARK: - App Cell

struct AppCell: View {
    let app: AppItem
    let assignments: [String: UUID]
    let categories: [AppCategory]
    let onAssign: (UUID?) -> Void
    let onUninstall: (() -> Void)?
    
    @State private var icon: NSImage?
    
    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            
            Text(app.displayName)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32)
            
            if let size = app.accurateSizeBytes ?? app.estimatedSizeBytes {
                Text(formatBytes(size))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 100)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .contextMenu {
            contextMenuItems
        }
        .onAppear {
            loadIcon()
        }
    }
    
    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Open") {
            NSWorkspace.shared.open(app.url)
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
        }
        Divider()
        
        // Category assignment submenu
        Menu("Assign to Category") {
            Button("None") {
                onAssign(nil)
            }
            Divider()
            ForEach(categories) { category in
                Button {
                    onAssign(category.id)
                } label: {
                    HStack {
                        Text(category.name)
                        if assignments[app.id] == category.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        
        if let onUninstall = onUninstall {
            Divider()
            Button("Uninstall...") {
                onUninstall()
            }
        }
    }
    
    private func loadIcon() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedIcon = NSWorkspace.shared.icon(forFile: app.url.path)
            loadedIcon.size = NSSize(width: 48, height: 48)
            DispatchQueue.main.async {
                self.icon = loadedIcon
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1000)
        } else if mb >= 1 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.0f KB", Double(bytes) / 1000)
        }
    }
}

// MARK: - Category Management Sheet

struct CategoryManagementSheet: View {
    @ObservedObject var viewModel: AppInventoryViewModel
    @State private var newCategoryName = ""
    @State private var editingCategoryID: UUID?
    @State private var editingName = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage Categories")
                .font(.headline)
            
            List {
                ForEach(viewModel.categories) { category in
                    HStack {
                        if editingCategoryID == category.id {
                            TextField("Name", text: $editingName, onCommit: {
                                if !editingName.isEmpty {
                                    viewModel.renameCategory(category.id, to: editingName)
                                }
                                editingCategoryID = nil
                            })
                            .textFieldStyle(.roundedBorder)
                            
                            Button {
                                if !editingName.isEmpty {
                                    viewModel.renameCategory(category.id, to: editingName)
                                }
                                editingCategoryID = nil
                            } label: {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.borderless)
                            
                            Button {
                                editingCategoryID = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Text(category.name)
                            Spacer()
                            Button {
                                editingCategoryID = category.id
                                editingName = category.name
                            } label: {
                                Image(systemName: "pencil")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.borderless)
                            
                            Button {
                                viewModel.deleteCategory(category.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .onMove { indices, destination in
                    viewModel.moveCategories(from: indices, to: destination)
                }
            }
            .frame(minHeight: 150)
            
            HStack {
                TextField("New Category", text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    if !newCategoryName.isEmpty {
                        viewModel.addCategory(name: newCategoryName)
                        newCategoryName = ""
                    }
                }
                .disabled(newCategoryName.isEmpty)
            }
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
