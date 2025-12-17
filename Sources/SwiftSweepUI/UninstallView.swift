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
        .sheet(isPresented: $viewModel.showingConfirmation) {
            if let plan = viewModel.deletionPlan {
                UninstallConfirmationSheet(
                    plan: plan,
                    viewModel: viewModel
                )
            }
        }
        .alert("卸载失败", isPresented: $viewModel.showingError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
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
                
                #if SWIFTSWEEP_MAS
                // MAS 版本：显示沙盒限制提示
                Button(action: {}) {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
                .disabled(true)
                #else
                // Developer ID 版本：可用
                Button(action: {
                    viewModel.prepareUninstall(app: app, residuals: residuals)
                }) {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.isDeleting || !viewModel.isHelperAvailable)
                #endif
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
            
            #if SWIFTSWEEP_MAS
            Text("⚠️ App Store 版不支持卸载功能（沙盒限制）")
                .font(.caption)
                .foregroundColor(.orange)
            #else
            if !viewModel.isHelperAvailable {
                HStack {
                    Text("⚠️ 需要安装 Helper 才能卸载应用")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    if #available(macOS 13.0, *) {
                        Button("安装 Helper") {
                            Task {
                                await viewModel.installHelper()
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
            }
            #endif
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

// MARK: - Confirmation Sheet

struct UninstallConfirmationSheet: View {
    let plan: DeletionPlan
    @ObservedObject var viewModel: UninstallViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "trash.fill")
                    .font(.title)
                    .foregroundColor(.red)
                VStack(alignment: .leading) {
                    Text("确认卸载")
                        .font(.headline)
                    Text(plan.app.name.replacingOccurrences(of: ".app", with: ""))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            
            Divider()
            
            // File List
            VStack(alignment: .leading, spacing: 8) {
                Text("将删除以下文件 (\(plan.items.count) 个项目，共 \(formatBytes(plan.totalSize)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                List {
                    ForEach(plan.items) { item in
                        DeletionItemRow(item: item, result: viewModel.itemResult(for: item))
                    }
                }
                .listStyle(.bordered)
                .frame(height: 250)
            }
            .padding()
            
            // Progress or Result
            if viewModel.isDeleting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在删除...")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if let result = viewModel.deletionResult {
                resultView(result)
                    .padding()
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("取消") {
                    dismiss()
                    viewModel.cancelUninstall()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                if let result = viewModel.deletionResult, !result.isComplete {
                    Button("重试失败项") {
                        Task {
                            await viewModel.retryFailedItems()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                if viewModel.deletionResult == nil {
                    Button("确认卸载") {
                        Task {
                            await viewModel.executeUninstall()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(viewModel.isDeleting)
                } else if viewModel.deletionResult?.isComplete == true {
                    Button("完成") {
                        dismiss()
                        viewModel.finishUninstall()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 500)
    }
    
    @ViewBuilder
    func resultView(_ result: DeletionResult) -> some View {
        if result.isComplete {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("卸载完成！已删除 \(result.successCount) 个项目")
            }
        } else {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading) {
                    Text("部分删除失败")
                    Text("成功: \(result.successCount) / 失败: \(result.failureCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
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

struct DeletionItemRow: View {
    let item: DeletionItem
    let result: DeletionItemResult?
    
    var body: some View {
        HStack {
            Image(systemName: iconForKind(item.kind))
                .foregroundColor(colorForKind(item.kind))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text((item.path as NSString).lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                Text(item.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let error = result?.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            if let result = result {
                if result.success {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            } else {
                Text(formatBytes(item.size))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    func iconForKind(_ kind: DeletionItemKind) -> String {
        switch kind {
        case .app: return "app.fill"
        case .cache: return "folder.fill"
        case .preferences: return "gearshape.fill"
        case .appSupport: return "folder.fill"
        case .launchAgent: return "gearshape.2.fill"
        case .container: return "shippingbox.fill"
        case .other: return "doc.fill"
        }
    }
    
    func colorForKind(_ kind: DeletionItemKind) -> Color {
        switch kind {
        case .app: return .blue
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
            return String(format: "%.1f GB", mb / 1024)
        } else if mb > 1 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
    }
}

// MARK: - ViewModel

@MainActor
class UninstallViewModel: ObservableObject {
    @Published var apps: [UninstallEngine.InstalledApp] = []
    @Published var selectedApp: UninstallEngine.InstalledApp?
    @Published var residualFiles: [UninstallEngine.ResidualFile] = []
    @Published var isScanning = false
    @Published var isLoadingResiduals = false
    
    // Uninstall state
    @Published var showingConfirmation = false
    @Published var deletionPlan: DeletionPlan?
    @Published var deletionResult: DeletionResult?
    @Published var isDeleting = false
    @Published var showingError = false
    @Published var errorMessage: String?
    
    #if !SWIFTSWEEP_MAS
    var isHelperAvailable: Bool {
        if #available(macOS 13.0, *) {
            return HelperClient.shared.checkStatus() == .enabled
        }
        return false
    }
    #else
    var isHelperAvailable: Bool { false }
    #endif
    
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
    
    // MARK: - Uninstall Actions
    
    func prepareUninstall(app: UninstallEngine.InstalledApp, residuals: [UninstallEngine.ResidualFile]) {
        // Create a copy of app with residuals
        var appWithResiduals = app
        appWithResiduals.residualFiles = residuals
        
        do {
            deletionPlan = try UninstallEngine.shared.createDeletionPlan(for: appWithResiduals)
            deletionResult = nil
            showingConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    #if !SWIFTSWEEP_MAS
    @available(macOS 13.0, *)
    func executeUninstall() async {
        guard let plan = deletionPlan else { return }
        
        isDeleting = true
        do {
            deletionResult = try await UninstallEngine.shared.executeDeletionPlan(plan)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isDeleting = false
    }
    
    @available(macOS 13.0, *)
    func retryFailedItems() async {
        guard let result = deletionResult else { return }
        
        isDeleting = true
        do {
            let retryResult = try await UninstallEngine.shared.retryFailedDeletions(result.failedItems)
            // Merge results
            var newResults = result.itemResults.filter { $0.success }
            newResults.append(contentsOf: retryResult.itemResults)
            deletionResult = DeletionResult(itemResults: newResults)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isDeleting = false
    }
    
    @available(macOS 13.0, *)
    func installHelper() async {
        do {
            try await HelperClient.shared.registerHelper()
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    #endif
    
    func cancelUninstall() {
        deletionPlan = nil
        deletionResult = nil
    }
    
    func finishUninstall() {
        // Remove uninstalled app from list
        if let plan = deletionPlan {
            apps.removeAll { $0.id == plan.app.id }
            selectedApp = nil
            residualFiles = []
        }
        deletionPlan = nil
        deletionResult = nil
    }
    
    func itemResult(for item: DeletionItem) -> DeletionItemResult? {
        deletionResult?.itemResults.first { $0.item.id == item.id }
    }
}
