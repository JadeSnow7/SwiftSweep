import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

// MARK: - Apple App Confirmation Sheet

struct AppleAppConfirmationSheet: View {
  let appName: String
  let onConfirm: () -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 48))
        .foregroundColor(.orange)

      Text("卸载 Apple 应用")
        .font(.headline)

      Text("您正在尝试卸载 \(appName)。这是 Apple 官方应用，卸载后可能需要从 App Store 重新下载。")
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)
        .padding(.horizontal)

      HStack(spacing: 16) {
        Button("取消") {
          onCancel()
        }
        .keyboardShortcut(.escape)

        Button("确认卸载") {
          onConfirm()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
      }
      .padding(.top, 8)
    }
    .padding(24)
    .frame(width: 380)
  }
}

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
      $0.name.lowercased().contains(searchText.lowercased())
        || $0.bundleID.lowercased().contains(searchText.lowercased())
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
          HStack(spacing: 8) {
            Text("Remove apps and their residual files")
              .foregroundColor(.secondary)

            // Background refresh indicator
            if viewModel.isBackgroundRefreshing {
              if let progress = viewModel.scanProgress {
                Text("(\(progress.current)/\(progress.total))")
                  .font(.caption)
                  .foregroundColor(.blue)
              }
              ProgressView()
                .scaleEffect(0.6)
            }
          }
        }
        Spacer()

        if viewModel.isScanning {
          ProgressView()
            .scaleEffect(0.8)
        } else if viewModel.isBackgroundRefreshing {
          Button(action: { viewModel.cancelScan() }) {
            Image(systemName: "xmark.circle")
          }
          .buttonStyle(.borderless)
          .help("Cancel background scan")
        } else {
          Button(action: { Task { await viewModel.scanApps() } }) {
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
    .sheet(isPresented: $viewModel.showingAppleAppConfirmation) {
      if let app = viewModel.pendingAppleApp {
        AppleAppConfirmationSheet(
          appName: app.name.replacingOccurrences(of: ".app", with: ""),
          onConfirm: {
            viewModel.showingAppleAppConfirmation = false
            viewModel.continueAppleAppUninstall()
          },
          onCancel: {
            viewModel.showingAppleAppConfirmation = false
            viewModel.pendingAppleApp = nil
          }
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
      // App Icon from actual app bundle
      Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
        .resizable()
        .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(app.name.replacingOccurrences(of: ".app", with: ""))
          .fontWeight(.medium)
        Text(app.bundleID)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      // Show size or placeholder
      if app.size > 0 {
        Text(formatBytes(app.size))
          .font(.callout)
          .foregroundColor(.secondary)
      } else {
        Text("—")
          .font(.callout)
          .foregroundColor(.secondary.opacity(0.5))
      }
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

        // Developer ID 版本：可用
        Button(action: {
          viewModel.prepareUninstall(app: app, residuals: residuals)
        }) {
          Label("Uninstall", systemImage: "trash")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(viewModel.isDeleting || !viewModel.isHelperAvailable)
      }

      if !residuals.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ResidualBadge(label: "App", size: app.size, color: .blue)

            ForEach(
              Array(
                Dictionary(grouping: residuals) { $0.type }.sorted(by: {
                  $0.key.rawValue < $1.key.rawValue
                })), id: \.key
            ) { type, files in
              let size = files.reduce(0) { $0 + $1.size }
              ResidualBadge(label: type.rawValue, size: size, color: colorForType(type))
            }
          }
        }
      }

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
      HStack(spacing: 12) {
        appIconView
          .frame(width: 44, height: 44)
          .cornerRadius(8)
        VStack(alignment: .leading, spacing: 4) {
          Text("确认卸载")
            .font(.headline)
          Text(appDisplayName)
            .foregroundColor(.secondary)
          Text("占用空间: \(appSizeText)")
            .font(.caption)
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

        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "info.circle")
            .foregroundColor(.secondary)
          Text("默认移动到废纸篓，可在废纸篓恢复。清空废纸篓后才会释放空间。")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)

        List {
          ForEach(plan.items) { item in
            DeletionItemRow(item: item, result: viewModel.itemResult(for: item))
          }
        }
        .listStyle(.bordered)
        .frame(height: 250)
      }
      .padding()

      if viewModel.isDeleting {
        VStack(spacing: 4) {
          HStack {
            ProgressView()
              .scaleEffect(0.8)
            if let progress = viewModel.deletionProgress {
              Text("正在删除... (\(progress.current)/\(progress.total))")
                .foregroundColor(.secondary)
            } else {
              Text("正在删除...")
                .foregroundColor(.secondary)
            }
          }
          if let currentItem = viewModel.deletionCurrentItem {
            Text(currentItem)
              .font(.caption)
              .foregroundColor(.secondary.opacity(0.7))
              .lineLimit(1)
          }
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

  private var appDisplayName: String {
    plan.app.name.replacingOccurrences(of: ".app", with: "")
  }

  private var appSizeText: String {
    let appItemSize = plan.items.first(where: { $0.kind == .app })?.size ?? 0
    if appItemSize > 0 {
      return formatBytes(appItemSize)
    }
    if plan.totalSize > 0 {
      return formatBytes(plan.totalSize)
    }
    return "—"
  }

  @ViewBuilder
  private var appIconView: some View {
    if FileManager.default.fileExists(atPath: plan.app.path) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: plan.app.path))
        .resizable()
    } else {
      Image(systemName: "app.fill")
        .resizable()
        .foregroundColor(.secondary)
    }
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

  // Apple App confirmation
  @Published var showingAppleAppConfirmation = false
  @Published var pendingAppleApp: UninstallEngine.InstalledApp?
  @Published var pendingResiduals: [UninstallEngine.ResidualFile] = []

  // Settings
  @AppStorage("allowAppleAppUninstall") private var allowAppleAppUninstall = false

  var isHelperAvailable: Bool {
    if #available(macOS 13.0, *) {
      return HelperClient.shared.checkStatus() == .enabled
    }
    return false
  }

  // SWR (Stale-While-Revalidate) scanning
  @Published var scanProgress: (current: Int, total: Int)?
  @Published var isBackgroundRefreshing = false
  private var scanTask: Task<Void, Never>?

  /// Scan apps with SWR pattern: load cache first, then background refresh
  func scanApps() async {
    // 1. Load from cache first (fast, < 200ms)
    let cached = UninstallCacheStore.shared.loadCachedApps()
    if !cached.isEmpty {
      apps = cached.map { $0.toInstalledApp() }
      // Show background refresh indicator instead of full scanning
      isBackgroundRefreshing = true
    } else {
      isScanning = true
    }

    // 2. Background scan for fresh data
    scanTask = Task.detached { [weak self] in
      guard let self = self else { return }

      do {
        let freshApps = try await UninstallEngine.shared.scanInstalledApps(includeSizes: true)

        // Convert to cached format
        let cachedApps = freshApps.map { CachedAppInfo(from: $0) }

        // Save all to cache at once
        UninstallCacheStore.shared.saveApps(cachedApps)

        // 3. Update UI with fresh data
        await MainActor.run {
          self.apps = freshApps
          self.isScanning = false
          self.isBackgroundRefreshing = false
          self.scanProgress = nil
        }

        // 4. Cleanup stale cache entries
        UninstallCacheStore.shared.cleanup()

      } catch {
        await MainActor.run {
          print("Error scanning apps: \(error)")
          self.isScanning = false
          self.isBackgroundRefreshing = false
          self.scanProgress = nil
        }
      }
    }
  }

  /// Cancel ongoing scan
  func cancelScan() {
    scanTask?.cancel()
    isScanning = false
    isBackgroundRefreshing = false
    scanProgress = nil
  }

  /// Load residuals with SWR pattern
  func loadResiduals(for app: UninstallEngine.InstalledApp) {
    isLoadingResiduals = true

    Task.detached { [weak self] in
      guard let self = self else { return }

      // 1. Load from cache first
      let cached = UninstallCacheStore.shared.loadResiduals(for: app.path)
      if !cached.isEmpty {
        let cachedResiduals = cached.map { $0.toResidualFile() }
        await MainActor.run {
          self.residualFiles = cachedResiduals
        }
      }

      // 2. Scan for fresh residuals in background
      do {
        let freshResiduals = try UninstallEngine.shared.findResidualFiles(for: app)

        // Convert and save to cache
        let cachedResiduals = freshResiduals.map { CachedResidualInfo(from: $0, appPath: app.path) }
        UninstallCacheStore.shared.saveResiduals(cachedResiduals, for: app.path)

        // Update UI
        await MainActor.run {
          self.residualFiles = freshResiduals
          self.isLoadingResiduals = false
        }
      } catch {
        await MainActor.run {
          print("Error finding residuals: \(error)")
          self.isLoadingResiduals = false
        }
      }
    }
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

  func prepareUninstall(
    app: UninstallEngine.InstalledApp, residuals: [UninstallEngine.ResidualFile]
  ) {
    // Check if this is an Apple App
    if PathValidator.isAppleApp(app) {
      if !allowAppleAppUninstall {
        errorMessage = "请在设置中开启 'Allow Apple App Uninstall' 后重试"
        showingError = true
        return
      }
      // Need confirmation for Apple Apps
      pendingAppleApp = app
      pendingResiduals = residuals
      showingAppleAppConfirmation = true
      return
    }

    // Non-Apple app, proceed directly
    performUninstallPreparation(app: app, residuals: residuals)
  }

  func continueAppleAppUninstall() {
    guard let app = pendingAppleApp else { return }
    performUninstallPreparation(app: app, residuals: pendingResiduals)
    pendingAppleApp = nil
    pendingResiduals = []
  }

  private func performUninstallPreparation(
    app: UninstallEngine.InstalledApp, residuals: [UninstallEngine.ResidualFile]
  ) {
    // Create a copy of app with residuals
    var appWithResiduals = app
    appWithResiduals.residualFiles = residuals

    // Run async deletion plan creation
    Task {
      do {
        deletionPlan = try await UninstallEngine.shared.createDeletionPlan(for: appWithResiduals)
        deletionResult = nil
        showingConfirmation = true
      } catch {
        errorMessage = error.localizedDescription
        showingError = true
      }
    }
  }

  // Deletion progress
  @Published var deletionProgress: (current: Int, total: Int)?
  @Published var deletionCurrentItem: String?

  @available(macOS 13.0, *)
  func executeUninstall() async {
    guard let plan = deletionPlan else { return }

    isDeleting = true
    deletionProgress = (0, plan.items.count)
    objectWillChange.send()

    do {
      deletionResult = try await UninstallEngine.shared.executeDeletionPlan(plan) {
        [weak self] current, total in
        // 使用 DispatchQueue.main 确保 UI 更新
        DispatchQueue.main.async {
          self?.deletionProgress = (current, total)
          // 显示当前正在删除的项目
          if current < plan.items.count {
            let itemPath = plan.items[current].path
            self?.deletionCurrentItem = (itemPath as NSString).lastPathComponent
          } else {
            self?.deletionCurrentItem = nil
          }
          // 强制 UI 刷新
          self?.objectWillChange.send()
        }
      }
    } catch {
      errorMessage = error.localizedDescription
      showingError = true
    }

    // 完成后显式更新 UI
    isDeleting = false
    deletionProgress = nil
    deletionCurrentItem = nil
    objectWillChange.send()
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
