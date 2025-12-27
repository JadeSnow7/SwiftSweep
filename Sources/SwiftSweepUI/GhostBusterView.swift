import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

/// Ghost Buster - 孤儿包检测视图
@available(macOS 13.0, *)
public struct GhostBusterView: View {
  @StateObject private var viewModel = GhostBusterViewModel()
  @State private var selectedNodes: Set<String> = []
  @State private var showingImpactAlert = false
  @State private var impactDetails: RemovalImpact?

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      // Header with stats
      headerView

      Divider()

      // Content
      if viewModel.isScanning {
        scanningView
      } else if let error = viewModel.error {
        errorView(error)
      } else if viewModel.orphanNodes.isEmpty && viewModel.hasScanned {
        emptyStateView
      } else if !viewModel.hasScanned {
        welcomeView
      } else {
        orphanListView
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await viewModel.scan() }
        } label: {
          Label("Scan", systemImage: "magnifyingglass")
        }
        .disabled(viewModel.isScanning)
      }
    }
    .navigationTitle("Ghost Buster")
    .alert("Impact Analysis", isPresented: $showingImpactAlert) {
      Button("OK") { impactDetails = nil }
    } message: {
      if let impact = impactDetails {
        Text(impactMessage(impact))
      }
    }
  }

  private func errorView(_ message: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 64))
        .foregroundColor(.orange)
      Text("Scan Error")
        .font(.title2)
      Text(message)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
      Button("Retry") {
        Task { await viewModel.scan() }
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Header

  private var headerView: some View {
    HStack(spacing: 20) {
      statBadge(
        icon: "shippingbox",
        value: "\(viewModel.stats?.totalNodes ?? 0)",
        label: "Total Packages",
        color: .blue
      )

      statBadge(
        icon: "figure.wave",
        value: "\(viewModel.orphanNodes.count)",
        label: "Orphans",
        color: .orange
      )

      if let stats = viewModel.stats {
        statBadge(
          icon: "internaldrive",
          value: formatBytes(stats.totalSize),
          label: "Total Size",
          color: .purple
        )
      }

      Spacer()

      if !selectedNodes.isEmpty {
        Button("Clear Selection") {
          selectedNodes.removeAll()
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
      }
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
  }

  private func statBadge(icon: String, value: String, label: String, color: Color) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundColor(color)
      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.headline)
        Text(label)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  // MARK: - Content Views

  private var scanningView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.5)
      Text("Scanning dependencies...")
        .font(.headline)
      Text("Building dependency graph and detecting orphan packages")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var welcomeView: some View {
    VStack(spacing: 16) {
      Image(systemName: "figure.wave")
        .font(.system(size: 64))
        .foregroundColor(.orange.opacity(0.6))
      Text("Ghost Buster")
        .font(.title)
      Text("Find orphan packages that are no longer needed")
        .foregroundColor(.secondary)
      Button("Start Scan") {
        Task { await viewModel.scan() }
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 64))
        .foregroundColor(.green)
      Text("No Orphan Packages Found")
        .font(.title2)
      Text("Your system is clean!")
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var orphanListView: some View {
    List(viewModel.orphanNodes, id: \.id, selection: $selectedNodes) { node in
      orphanRow(node)
    }
  }

  private func orphanRow(_ node: PackageNode) -> some View {
    HStack {
      // Ecosystem icon
      ecosystemIcon(node.identity.ecosystemId)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(node.identity.name)
            .font(.headline)

          Text(node.identity.version.normalized)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(4)
        }

        if let path = node.metadata.installPath {
          Text(path)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      Spacer()

      if let size = node.metadata.size {
        Text(formatBytes(size))
          .font(.caption)
          .foregroundColor(.blue)
      }

      Button {
        Task { await analyzeImpact(node) }
      } label: {
        Image(systemName: "info.circle")
      }
      .buttonStyle(.plain)
      .help("Analyze removal impact")
    }
    .padding(.vertical, 4)
  }

  private func ecosystemIcon(_ id: String) -> some View {
    let (icon, color): (String, Color) =
      switch id {
      case "homebrew_formula": ("cup.and.saucer", .orange)
      case "homebrew_cask": ("macwindow", .orange)
      case "npm": ("shippingbox", .red)
      case "pip": ("cube", .blue)
      case "gem": ("diamond.fill", .pink)
      default: ("shippingbox", .gray)
      }

    return Image(systemName: icon)
      .foregroundColor(color)
  }

  // MARK: - Actions

  private func analyzeImpact(_ node: PackageNode) async {
    do {
      let impact = try await viewModel.analyzeImpact(of: node)
      impactDetails = impact
      showingImpactAlert = true
    } catch {
      // Handle error
    }
  }

  private func impactMessage(_ impact: RemovalImpact) -> String {
    if impact.isSafeToRemove {
      return "This package can be safely removed. No other packages depend on it."
    } else {
      return
        "Warning: \(impact.totalAffected) package(s) may be affected by removing this package.\n\nDirect dependents: \(impact.directDependents.map { $0.name }.joined(separator: ", "))"
    }
  }

  // MARK: - Helpers

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

// MARK: - ViewModel

@available(macOS 13.0, *)
@MainActor
class GhostBusterViewModel: ObservableObject {
  @Published var orphanNodes: [PackageNode] = []
  @Published var stats: GraphStatistics?
  @Published var isScanning = false
  @Published var hasScanned = false
  @Published var error: String?

  private let service = DependencyGraphService.shared

  func scan() async {
    isScanning = true
    error = nil

    print("[GhostBuster] Starting scan...")

    do {
      print("[GhostBuster] Initializing service...")
      try await service.initialize()

      print("[GhostBuster] Scanning all providers...")
      let result = await service.scanAll()

      print("[GhostBuster] Scan complete: \(result.nodeCount) nodes, \(result.edgeCount) edges")
      if !result.errors.isEmpty {
        print("[GhostBuster] Errors: \(result.errors.map { $0.message })")
      }

      if !result.isSuccess && result.nodeCount == 0 {
        error = result.errors.first?.message ?? "Scan failed with no packages found"
      }

      print("[GhostBuster] Getting orphan nodes...")
      orphanNodes = try await service.getOrphanNodes()
      print("[GhostBuster] Found \(orphanNodes.count) orphans")

      stats = try await service.getStatistics()
      hasScanned = true
    } catch {
      print("[GhostBuster] Error: \(error)")
      self.error = error.localizedDescription
    }

    isScanning = false
    print("[GhostBuster] Scan finished, isScanning = false")
  }

  func analyzeImpact(of node: PackageNode) async throws -> RemovalImpact {
    try await service.simulateRemoval(of: node)
  }
}
