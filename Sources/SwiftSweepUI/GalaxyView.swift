import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

// MARK: - GalaxyView

/// Dependency graph visualization as a galaxy of nodes
public struct GalaxyView: View {
  @StateObject private var viewModel = GalaxyViewModel()

  public init() {}

  public var body: some View {
    ZStack {
      // Background
      Color(nsColor: .windowBackgroundColor)
        .ignoresSafeArea()

      if viewModel.isLoading {
        loadingView
      } else if viewModel.nodes.isEmpty {
        emptyView
      } else {
        galaxyCanvas
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: { Task { await viewModel.refresh() } }) {
          Image(systemName: "arrow.clockwise")
        }
        .help("Refresh")
      }
    }
    .task {
      await viewModel.loadGraph()
    }
  }

  // MARK: - Canvas

  private var galaxyCanvas: some View {
    GeometryReader { geometry in
      ZStack {
        // Edges layer
        Canvas { context, size in
          for edge in viewModel.visibleEdges {
            let path = Path { p in
              p.move(to: edge.sourcePosition)
              p.addLine(to: edge.targetPosition)
            }
            context.stroke(path, with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
          }
        }

        // Nodes layer
        ForEach(viewModel.visibleNodes) { node in
          nodeView(for: node)
        }

        // Clusters layer (when in cluster LOD)
        ForEach(viewModel.clusters) { cluster in
          if viewModel.lodLevel == .cluster {
            clusterView(for: cluster)
          }
        }

        // Legend
        legendView
          .position(x: geometry.size.width - 80, y: 60)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .gesture(magnificationGesture)
      .gesture(dragGesture)
      .onAppear {
        viewModel.canvasSize = geometry.size
      }
      .onChange(of: geometry.size) { newSize in
        viewModel.canvasSize = newSize
        Task { await viewModel.recomputeLayout() }
      }
    }
  }

  // MARK: - Node View

  private func nodeView(for node: VisualNode) -> some View {
    Circle()
      .fill(node.color.opacity(node.isSelected ? 1.0 : 0.7))
      .frame(width: node.radius * 2, height: node.radius * 2)
      .overlay(
        Circle()
          .stroke(node.isSelected ? Color.white : Color.clear, lineWidth: 2)
      )
      .position(node.position)
      .onTapGesture {
        viewModel.selectNode(node.id)
      }
      .help(node.displayName)
  }

  // MARK: - Cluster View

  private func clusterView(for cluster: ClusterInfo) -> some View {
    ZStack {
      Circle()
        .fill(cluster.color.opacity(0.5))
        .frame(width: cluster.radius * 2, height: cluster.radius * 2)

      VStack(spacing: 2) {
        Text(cluster.displayName)
          .font(.caption.bold())
          .foregroundColor(.white)
        Text("\(cluster.nodeCount)")
          .font(.caption2)
          .foregroundColor(.white.opacity(0.8))
      }
    }
    .position(cluster.position)
  }

  // MARK: - Legend

  private var legendView: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Ecosystems")
        .font(.caption.bold())

      legendItem(color: .orange, label: "Homebrew")
      legendItem(color: .green, label: "npm")
      legendItem(color: .blue, label: "Python")
      legendItem(color: .red, label: "Ruby")
    }
    .padding(8)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
  }

  private func legendItem(color: Color, label: String) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
      Text(label)
        .font(.caption2)
    }
  }

  // MARK: - Gestures

  private var magnificationGesture: some Gesture {
    MagnificationGesture()
      .onChanged { scale in
        viewModel.zoomScale = scale
      }
  }

  private var dragGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        viewModel.panOffset = value.translation
      }
  }

  // MARK: - State Views

  private var loadingView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.5)
      Text("Loading dependency graph...")
        .foregroundColor(.secondary)
    }
  }

  private var emptyView: some View {
    VStack(spacing: 16) {
      Image(systemName: "circle.hexagongrid")
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("No packages found")
        .font(.headline)
      Text("Run Ghost Buster scan first")
        .foregroundColor(.secondary)
    }
  }
}

// MARK: - GalaxyViewModel

@MainActor
class GalaxyViewModel: ObservableObject {
  @Published var nodes: [VisualNode] = []
  @Published var edges: [VisualEdge] = []
  @Published var clusters: [ClusterInfo] = []
  @Published var isLoading = false
  @Published var zoomScale: CGFloat = 1.0
  @Published var panOffset: CGSize = .zero
  @Published var selectedNodeId: String?

  var canvasSize: CGSize = CGSize(width: 800, height: 600)

  private let layoutEngine = GraphLayoutEngine()
  private let graphService = DependencyGraphService.shared

  var lodLevel: LODLevel {
    LODLevel(zoomScale: zoomScale)
  }

  var visibleNodes: [VisualNode] {
    switch lodLevel {
    case .cluster:
      return []
    case .overview:
      return Array(nodes.sorted { ($0.size ?? 0) > ($1.size ?? 0) }.prefix(50))
    case .detail:
      return nodes
    }
  }

  var visibleEdges: [VisualEdge] {
    let visibleIds = Set(visibleNodes.map { $0.id })
    return edges.filter { visibleIds.contains($0.sourceId) || visibleIds.contains($0.targetId) }
  }

  func loadGraph() async {
    isLoading = true
    defer { isLoading = false }

    do {
      try await graphService.initialize()
      let snapshot = try await graphService.getGraphSnapshot()

      // Convert to visual models
      nodes = snapshot.nodes.map { VisualNode(from: $0) }

      // Create visual edges
      edges = snapshot.edges.compactMap { edge in
        VisualEdge(from: edge)
      }

      // Compute layout
      await recomputeLayout()

      // Create clusters
      let nodesByEcosystem = Dictionary(grouping: nodes) { $0.ecosystemId }
      clusters = nodesByEcosystem.map { ecosystemId, ecosystemNodes in
        ClusterInfo(ecosystemId: ecosystemId, nodes: ecosystemNodes)
      }
    } catch {
      print("[Galaxy] Error loading graph: \(error)")
    }
  }

  func refresh() async {
    let result = await graphService.scanAll()
    print("[Galaxy] Scan complete: \(result.nodeCount) nodes, \(result.edgeCount) edges")
    await loadGraph()
  }

  func recomputeLayout() async {
    let result = await layoutEngine.computeLayout(
      nodes: nodes,
      edges: edges,
      canvasSize: canvasSize
    )

    // Apply positions
    for i in nodes.indices {
      if let pos = result.nodePositions[nodes[i].id] {
        nodes[i].position = pos
      }
    }

    // Update edges
    let nodePositions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
    for i in edges.indices {
      edges[i].sourcePosition = nodePositions[edges[i].sourceId] ?? .zero
      // Find target by matching ecosystem::name pattern
      let targetPos =
        nodes.first { n in
          "\(n.ecosystemId)::\(n.name)" == edges[i].targetId || n.id == edges[i].targetId
        }?.position ?? .zero
      edges[i].targetPosition = targetPos
    }

    // Update cluster positions
    for i in clusters.indices {
      if let pos = result.clusterPositions[clusters[i].id] {
        clusters[i].position = pos
      }
    }
  }

  func selectNode(_ id: String) {
    if selectedNodeId == id {
      selectedNodeId = nil
    } else {
      selectedNodeId = id
    }

    for i in nodes.indices {
      nodes[i].isSelected = nodes[i].id == selectedNodeId
    }
  }
}

#Preview {
  GalaxyView()
    .frame(width: 800, height: 600)
}
