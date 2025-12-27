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

      // Node detail panel (when node selected)
      if let selectedNode = viewModel.selectedNode {
        nodeDetailPanel(for: selectedNode)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          .padding()
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        // Force layout toggle
        Toggle(isOn: $viewModel.useForceLayout) {
          Label("Force Layout", systemImage: "atom")
        }
        .toggleStyle(.button)
        .help(viewModel.useForceLayout ? "Using force-directed layout" : "Using static layout")

        // Simulation progress
        if viewModel.isSimulating {
          ProgressView(value: viewModel.simulationProgress)
            .frame(width: 60)
        }

        Divider()

        // Zoom slider
        HStack(spacing: 4) {
          Image(systemName: "minus.magnifyingglass")
            .foregroundColor(.secondary)
          Slider(value: $viewModel.zoomScale, in: 0.1...3.0)
            .frame(width: 100)
          Image(systemName: "plus.magnifyingglass")
            .foregroundColor(.secondary)
          Text("\(Int(viewModel.zoomScale * 100))%")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(width: 40)
        }

        Button(action: { viewModel.resetView() }) {
          Image(systemName: "arrow.counterclockwise")
        }
        .help("Reset View")

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
      let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

      ZStack {
        // Edges layer
        Canvas { context, size in
          // Edge opacity decreases when zoomed out, increases when zoomed in
          let baseOpacity = min(0.6, 0.2 + viewModel.zoomScale * 0.2)

          for edge in viewModel.visibleEdges {
            let sourcePos = transformPoint(edge.sourcePosition, center: center)
            let targetPos = transformPoint(edge.targetPosition, center: center)

            let path = Path { p in
              p.move(to: sourcePos)
              p.addLine(to: targetPos)
            }

            // Use edge color with zoom-dependent opacity
            context.stroke(
              path,
              with: .color(edge.color.opacity(baseOpacity)),
              lineWidth: max(0.5, 1.0 * viewModel.zoomScale)
            )
          }
        }

        // Nodes layer - use transformed position directly
        ForEach(viewModel.visibleNodes) { node in
          let transformedPos = transformPoint(node.position, center: center)
          nodeView(for: node)
            .position(transformedPos)
        }

        // Clusters layer (when in cluster LOD)
        if viewModel.lodLevel == .cluster {
          ForEach(viewModel.clusters) { cluster in
            let transformedPos = transformPoint(cluster.position, center: center)
            clusterView(for: cluster)
              .position(transformedPos)
          }
        }

        // Legend
        legendView
          .position(x: geometry.size.width - 80, y: 60)

        // Stats overlay
        statsOverlay
          .position(x: 80, y: 30)
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
      .frame(
        width: node.radius * 2 * viewModel.zoomScale, height: node.radius * 2 * viewModel.zoomScale
      )
      .overlay(
        Circle()
          .stroke(node.isSelected ? Color.white : Color.clear, lineWidth: 2)
      )
      .shadow(color: node.isSelected ? node.color : .clear, radius: 5)
      .scaleEffect(viewModel.hoveredNodeId == node.id ? 1.2 : 1.0)
      .animation(.easeInOut(duration: 0.15), value: viewModel.hoveredNodeId)
      .onHover { isHovered in
        viewModel.hoveredNodeId = isHovered ? node.id : nil
      }
      .onTapGesture(count: 2) {
        // Double-click: focus on node
        viewModel.focusOnNode(node.id)
      }
      .onTapGesture {
        viewModel.selectNode(node.id)
      }
      .contextMenu {
        Button {
          viewModel.selectNode(node.id)
        } label: {
          Label("Select", systemImage: "hand.tap")
        }

        Button {
          viewModel.focusOnNode(node.id)
        } label: {
          Label("Focus", systemImage: "scope")
        }

        Divider()

        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(node.displayName, forType: .string)
        } label: {
          Label("Copy Name", systemImage: "doc.on.doc")
        }

        if let path = node.identity.scope.map({ "\($0)/\(node.name)" }) ?? node.name as String? {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
          } label: {
            Label("Copy Full Path", systemImage: "rectangle.on.rectangle")
          }
        }
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

  // MARK: - Node Detail Panel

  private func nodeDetailPanel(for node: VisualNode) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Circle()
          .fill(node.color)
          .frame(width: 12, height: 12)
        Text(node.displayName)
          .font(.headline)
        Spacer()
        Button(action: { viewModel.selectedNodeId = nil }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }

      Divider()

      LabeledContent("Ecosystem", value: node.ecosystemId)
      if let size = node.size {
        LabeledContent(
          "Size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
      }
      LabeledContent("Version", value: node.identity.version.normalized)
    }
    .padding()
    .frame(width: 250)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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

  // MARK: - Stats Overlay

  private var statsOverlay: some View {
    HStack(spacing: 12) {
      Label("\(viewModel.nodes.count)", systemImage: "circle.fill")
      Label("\(viewModel.edges.count)", systemImage: "line.diagonal")
    }
    .font(.caption)
    .foregroundColor(.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(.ultraThinMaterial, in: Capsule())
  }

  // MARK: - Gestures

  private var magnificationGesture: some Gesture {
    MagnificationGesture()
      .onChanged { scale in
        viewModel.zoomScale = viewModel.baseZoom * scale
      }
      .onEnded { scale in
        viewModel.baseZoom = viewModel.zoomScale
      }
  }

  private var dragGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        viewModel.offset = CGSize(
          width: viewModel.baseOffset.width + value.translation.width,
          height: viewModel.baseOffset.height + value.translation.height
        )
      }
      .onEnded { value in
        viewModel.baseOffset = viewModel.offset
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

  // MARK: - Transform Helper

  /// Transform a point with zoom (centered on canvas center) and pan offset
  private func transformPoint(_ point: CGPoint, center: CGPoint) -> CGPoint {
    // Scale around center
    let scaledX = center.x + (point.x - center.x) * viewModel.zoomScale
    let scaledY = center.y + (point.y - center.y) * viewModel.zoomScale

    // Apply pan offset
    return CGPoint(
      x: scaledX + viewModel.offset.width,
      y: scaledY + viewModel.offset.height
    )
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
  @Published var offset: CGSize = .zero
  @Published var selectedNodeId: String?
  @Published var hoveredNodeId: String?
  @Published var useForceLayout = false {
    didSet {
      if useForceLayout {
        Task { await runForceLayout() }
      }
    }
  }
  @Published var isSimulating = false
  @Published var simulationProgress: Double = 0

  // Base values for cumulative gestures
  var baseZoom: CGFloat = 1.0
  var baseOffset: CGSize = .zero

  // Simulation task
  private var simulationTask: Task<Void, Never>?

  var canvasSize: CGSize = CGSize(width: 800, height: 600)

  private let layoutEngine = GraphLayoutEngine()
  private let graphService = DependencyGraphService.shared

  var lodLevel: LODLevel {
    LODLevel(zoomScale: zoomScale)
  }

  var selectedNode: VisualNode? {
    guard let id = selectedNodeId else { return nil }
    return nodes.first { $0.id == id }
  }

  /// Viewport rectangle for culling
  var viewportRect: CGRect {
    // Calculate visible area based on zoom and offset
    let visibleWidth = canvasSize.width / zoomScale
    let visibleHeight = canvasSize.height / zoomScale
    let centerX = canvasSize.width / 2 - offset.width / zoomScale
    let centerY = canvasSize.height / 2 - offset.height / zoomScale

    return CGRect(
      x: centerX - visibleWidth / 2,
      y: centerY - visibleHeight / 2,
      width: visibleWidth,
      height: visibleHeight
    ).insetBy(dx: -50, dy: -50)  // Add margin for nodes near edge
  }

  var visibleNodes: [VisualNode] {
    // Sort by size for LOD
    let sortedNodes = nodes.sorted { ($0.size ?? 0) > ($1.size ?? 0) }

    switch lodLevel {
    case .cluster:
      return []
    case .overview:
      // Top 50 largest nodes
      return Array(sortedNodes.prefix(50))
    case .detail:
      // Apply viewport culling for large graphs
      if nodes.count > 200 {
        // For very large graphs, limit to top 100 + viewport culling
        let topNodes = Set(sortedNodes.prefix(100).map { $0.id })
        return nodes.filter { node in
          topNodes.contains(node.id) || viewportRect.contains(node.position)
        }
      } else {
        return nodes
      }
    }
  }

  var visibleEdges: [VisualEdge] {
    let visibleIds = Set(visibleNodes.map { $0.id })

    // For large edge counts, limit to those connecting visible nodes
    let filtered = edges.filter { edge in
      visibleIds.contains(edge.sourceId)
        && (visibleIds.contains(edge.targetId)
          || nodes.contains { n in
            "\(n.ecosystemId)::\(n.name)" == edge.targetId && visibleIds.contains(n.id)
          })
    }

    // Further limit if still too many
    if filtered.count > 500 {
      return Array(filtered.prefix(500))
    }
    return filtered
  }

  func resetView() {
    zoomScale = 1.0
    baseZoom = 1.0
    offset = .zero
    baseOffset = .zero
    simulationTask?.cancel()
    isSimulating = false
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

  func runForceLayout() async {
    // Cancel any existing simulation
    simulationTask?.cancel()

    isSimulating = true
    simulationProgress = 0

    let stream = await layoutEngine.computeForceLayout(
      nodes: nodes,
      edges: edges,
      canvasSize: canvasSize
    )

    simulationTask = Task {
      for await update in stream {
        // Apply positions with animation
        withAnimation(.easeInOut(duration: 0.05)) {
          for i in nodes.indices {
            if let pos = update.positions[nodes[i].id] {
              nodes[i].position = pos
            }
          }

          // Update edge positions
          for i in edges.indices {
            edges[i].sourcePosition = nodes.first { $0.id == edges[i].sourceId }?.position ?? .zero
            let targetPos =
              nodes.first { n in
                "\(n.ecosystemId)::\(n.name)" == edges[i].targetId || n.id == edges[i].targetId
              }?.position ?? .zero
            edges[i].targetPosition = targetPos
          }
        }

        simulationProgress = update.progress

        if update.isComplete {
          isSimulating = false
          break
        }
      }

      isSimulating = false
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

  func focusOnNode(_ id: String) {
    guard let node = nodes.first(where: { $0.id == id }) else { return }

    // Center the view on this node
    withAnimation(.easeInOut(duration: 0.3)) {
      // Calculate offset to center node in canvas
      let targetOffset = CGSize(
        width: canvasSize.width / 2 - node.position.x,
        height: canvasSize.height / 2 - node.position.y
      )
      offset = targetOffset
      baseOffset = targetOffset

      // Zoom in to 150%
      zoomScale = 1.5
      baseZoom = 1.5

      // Select the node
      selectedNodeId = id
      for i in nodes.indices {
        nodes[i].isSelected = nodes[i].id == id
      }
    }
  }
}

#Preview {
  GalaxyView()
    .frame(width: 800, height: 600)
}
