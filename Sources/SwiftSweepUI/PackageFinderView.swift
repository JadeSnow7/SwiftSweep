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

    // Operation confirmation state
    @State private var showingConfirmation = false
    @State private var pendingOperation: PendingOperation?
    @State private var operationResult: PackageOperationResult?
    @State private var showingResult = false

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
          .disabled(viewModel.isScanning || viewModel.isOperating)
        }
      }
      .task {
        await viewModel.scan()
      }
      .navigationTitle("Packages")
      .sheet(isPresented: $showingConfirmation) {
        if let op = pendingOperation {
          PackageOperationConfirmSheet(
            operation: op,
            onConfirm: {
              showingConfirmation = false
              Task { await executeOperation(op) }
            },
            onCancel: {
              showingConfirmation = false
              pendingOperation = nil
            }
          )
        }
      }
      .alert("Operation Result", isPresented: $showingResult) {
        Button("OK") { operationResult = nil }
      } message: {
        Text(operationResult?.message ?? "")
      }
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
        } else if viewModel.isOperating {
          ProgressView()
            .scaleEffect(0.7)
          Text("Operating...")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          let totalPackages = viewModel.results.reduce(0) { $0 + $1.packages.count }
          Text(
            "\(totalPackages) packages from \(viewModel.results.filter { if case .ok = $0.status { return true } else { return false } }.count) sources"
          )
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
          .font(.system(size: 48))
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
              packageRow(package, result: result)
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

    private func packageRow(_ package: Package, result: PackageScanResult) -> some View {
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
        // Copy actions
        Button("Copy Name") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(package.name, forType: .string)
        }
        Button("Copy Name@Version") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString("\(package.name)@\(package.version)", forType: .string)
        }

        Divider()

        // Operation actions (capability-based)
        let provider = viewModel.getOperator(for: result.providerID)

        if provider?.capabilities.contains(.update) == true {
          Button {
            prepareOperation(.update, package: package, provider: provider!)
          } label: {
            Label("Update", systemImage: "arrow.up.circle")
          }
        }

        if provider?.capabilities.contains(.uninstall) == true {
          Button(role: .destructive) {
            prepareOperation(.uninstall, package: package, provider: provider!)
          } label: {
            Label("Uninstall", systemImage: "trash")
          }
        }

        if let cmd = provider?.uninstallCommand(for: package), !cmd.isEmpty {
          Divider()
          Button("Copy Uninstall Command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
          }
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

    // MARK: - Operations

    private func prepareOperation(
      _ type: OperationType, package: Package, provider: any PackageOperator
    ) {
      let command: String
      switch type {
      case .uninstall:
        command = provider.uninstallCommand(for: package)
      case .update:
        command = provider.updateCommand(for: package)
      }

      pendingOperation = PendingOperation(
        type: type,
        package: package,
        providerID: provider.id,
        executablePath: provider.executablePath ?? "unknown",
        command: command
      )
      showingConfirmation = true
    }

    private func executeOperation(_ op: PendingOperation) async {
      guard let provider = viewModel.getOperator(for: op.providerID) else { return }

      let result: PackageOperationResult
      switch op.type {
      case .uninstall:
        result = await provider.uninstall(op.package)
      case .update:
        result = await provider.update(op.package)
      }

      operationResult = result
      showingResult = true

      // Refresh after operation
      if result.success {
        await viewModel.scan()
      }
    }

    // MARK: - Helpers

    private func filteredPackages(_ packages: [Package]) -> [Package] {
      guard !searchText.isEmpty else { return packages }
      let query = searchText.lowercased()
      return packages.filter {
        $0.name.lowercased().contains(query) || $0.version.lowercased().contains(query)
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

  // MARK: - Operation Types

  @available(macOS 13.0, *)
  enum OperationType {
    case uninstall
    case update

    var title: String {
      switch self {
      case .uninstall: return "Uninstall"
      case .update: return "Update"
      }
    }

    var icon: String {
      switch self {
      case .uninstall: return "trash"
      case .update: return "arrow.up.circle"
      }
    }
  }

  @available(macOS 13.0, *)
  struct PendingOperation {
    let type: OperationType
    let package: Package
    let providerID: String
    let executablePath: String
    let command: String
  }

  // MARK: - Confirmation Sheet

  @available(macOS 13.0, *)
  struct PackageOperationConfirmSheet: View {
    let operation: PendingOperation
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
      VStack(spacing: 16) {
        // Header
        HStack {
          Image(systemName: operation.type.icon)
            .font(.title)
            .foregroundColor(operation.type == .uninstall ? .red : .accentColor)
          VStack(alignment: .leading) {
            Text("\(operation.type.title) Package")
              .font(.headline)
            Text(operation.package.name)
              .foregroundColor(.secondary)
          }
          Spacer()
        }

        Divider()

        // Details
        VStack(alignment: .leading, spacing: 8) {
          DetailRow(label: "Package", value: operation.package.name)
          DetailRow(label: "Version", value: operation.package.version)
          DetailRow(label: "Executable", value: operation.executablePath)

          Text("Command to execute:")
            .font(.caption)
            .foregroundColor(.secondary)

          Text(operation.command)
            .font(.system(.caption, design: .monospaced))
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
            .textSelection(.enabled)
        }

        // Warning for pip/npm
        if operation.providerID == "pip" || operation.providerID == "npm" {
          HStack {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.orange)
            Text("Multiple environments may exist. Verify the executable path is correct.")
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .padding(8)
          .background(Color.orange.opacity(0.1))
          .cornerRadius(4)
        }

        Divider()

        // Actions
        HStack {
          Button("Copy Command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(operation.command, forType: .string)
          }
          .buttonStyle(.bordered)

          Spacer()

          Button("Cancel", role: .cancel) {
            onCancel()
          }
          .keyboardShortcut(.escape)

          Button(operation.type.title) {
            onConfirm()
          }
          .buttonStyle(.borderedProminent)
          .tint(operation.type == .uninstall ? .red : .accentColor)
        }
      }
      .padding()
      .frame(width: 450)
    }
  }

  @available(macOS 13.0, *)
  struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
      HStack {
        Text(label)
          .foregroundColor(.secondary)
          .frame(width: 80, alignment: .trailing)
        Text(value)
          .fontWeight(.medium)
        Spacer()
      }
    }
  }

  // MARK: - View Model

  @available(macOS 13.0, *)
  @MainActor
  final class PackageFinderViewModel: ObservableObject {
    @Published var results: [PackageScanResult] = []
    @Published var isScanning = false
    @Published var isOperating = false
    @Published var lastScanTime: Date?

    private let scanner = PackageScanner.shared
    private let providers: [any PackageOperator] = [
      HomebrewFormulaProvider(),
      HomebrewCaskProvider(),
      NpmProvider(),
      PipProvider(),
      GemProvider(),
    ]

    func scan() async {
      guard !isScanning else { return }
      isScanning = true
      defer { isScanning = false }

      results = await scanner.scanAll()
      lastScanTime = Date()
    }

    func getOperator(for providerID: String) -> (any PackageOperator)? {
      providers.first { $0.id == providerID }
    }
  }

#endif
