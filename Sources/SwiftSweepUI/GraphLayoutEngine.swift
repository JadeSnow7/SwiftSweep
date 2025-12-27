import Foundation
import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

// MARK: - GraphLayoutEngine

/// Computes layout positions for galaxy visualization
/// Uses cluster-based layout: clusters first, then nodes within clusters
public actor GraphLayoutEngine {

  // MARK: - Public API

  /// Compute static layout for all nodes
  public func computeLayout(
    nodes: [VisualNode],
    edges: [VisualEdge],
    canvasSize: CGSize
  ) -> LayoutResult {
    // Group nodes by ecosystem
    let nodesByEcosystem = Dictionary(grouping: nodes) { $0.ecosystemId }

    // Create clusters
    var clusters: [ClusterInfo] = nodesByEcosystem.map { ecosystemId, ecosystemNodes in
      ClusterInfo(ecosystemId: ecosystemId, nodes: ecosystemNodes)
    }

    // Position clusters in a circle
    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    let clusterRadius = min(canvasSize.width, canvasSize.height) * 0.35

    for (index, _) in clusters.enumerated() {
      let angle = 2 * .pi * Double(index) / Double(clusters.count) - .pi / 2
      clusters[index].position = CGPoint(
        x: center.x + CGFloat(cos(angle)) * clusterRadius,
        y: center.y + CGFloat(sin(angle)) * clusterRadius
      )
    }

    // Position nodes within their clusters
    var nodePositions: [String: CGPoint] = [:]

    for cluster in clusters {
      let clusterNodes = nodesByEcosystem[cluster.ecosystemId] ?? []
      let positions = layoutNodesInCluster(
        nodes: clusterNodes,
        clusterCenter: cluster.position,
        clusterRadius: cluster.radius
      )
      nodePositions.merge(positions) { _, new in new }
    }

    let clusterPositions = Dictionary(uniqueKeysWithValues: clusters.map { ($0.id, $0.position) })

    return LayoutResult(nodePositions: nodePositions, clusterPositions: clusterPositions)
  }

  /// Compute layout with LOD filtering
  public func computeLayoutWithLOD(
    nodes: [VisualNode],
    edges: [VisualEdge],
    canvasSize: CGSize,
    lodLevel: LODLevel,
    viewportRect: CGRect? = nil
  ) -> (nodes: [VisualNode], clusters: [ClusterInfo], layout: LayoutResult) {
    // Full layout first
    let fullLayout = computeLayout(nodes: nodes, edges: edges, canvasSize: canvasSize)

    // Apply positions to nodes
    let positionedNodes = nodes.map { node in
      var n = node
      n.position = fullLayout.nodePositions[node.id] ?? node.position
      return n
    }

    // Group for clusters
    let nodesByEcosystem = Dictionary(grouping: positionedNodes) { $0.ecosystemId }
    let clusters: [ClusterInfo] = nodesByEcosystem.map { ecosystemId, ecosystemNodes in
      var c = ClusterInfo(ecosystemId: ecosystemId, nodes: ecosystemNodes)
      c.position = fullLayout.clusterPositions[c.id] ?? c.position
      return c
    }

    // Filter based on LOD
    let visibleNodes: [VisualNode]
    switch lodLevel {
    case .cluster:
      visibleNodes = []  // Only show clusters
    case .overview:
      // Top 50 nodes by size
      visibleNodes = Array(positionedNodes.sorted { ($0.size ?? 0) > ($1.size ?? 0) }.prefix(50))
    case .detail:
      // All nodes (optionally filtered by viewport)
      if let viewport = viewportRect {
        visibleNodes = positionedNodes.filter { viewport.contains($0.position) }
      } else {
        visibleNodes = positionedNodes
      }
    }

    return (visibleNodes, clusters, fullLayout)
  }

  // MARK: - Private

  private func layoutNodesInCluster(
    nodes: [VisualNode],
    clusterCenter: CGPoint,
    clusterRadius: CGFloat
  ) -> [String: CGPoint] {
    var positions: [String: CGPoint] = [:]

    guard !nodes.isEmpty else { return positions }

    if nodes.count == 1 {
      positions[nodes[0].id] = clusterCenter
      return positions
    }

    // Spiral layout for nodes within cluster
    let nodeSpacing: CGFloat = 25
    var currentRadius: CGFloat = 0
    var currentAngle: Double = 0
    var nodesPlaced = 0
    var currentRingCapacity = 1
    var nodesInCurrentRing = 0

    for node in nodes.sorted(by: { ($0.size ?? 0) > ($1.size ?? 0) }) {
      if nodesInCurrentRing >= currentRingCapacity {
        // Move to next ring
        currentRadius += nodeSpacing
        currentRingCapacity = max(1, Int(2 * .pi * currentRadius / nodeSpacing))
        nodesInCurrentRing = 0
        currentAngle = 0
      }

      let x = clusterCenter.x + cos(currentAngle) * currentRadius
      let y = clusterCenter.y + sin(currentAngle) * currentRadius
      positions[node.id] = CGPoint(x: x, y: y)

      currentAngle += 2 * .pi / Double(currentRingCapacity)
      nodesInCurrentRing += 1
      nodesPlaced += 1
    }

    return positions
  }

  // MARK: - Force-Directed Layout

  /// Parameters for force-directed simulation
  public struct ForceLayoutParams: Sendable {
    public var repulsionStrength: CGFloat = 5000
    public var attractionStrength: CGFloat = 0.01
    public var damping: CGFloat = 0.85
    public var maxIterations: Int = 200
    public var convergenceThreshold: CGFloat = 0.5

    public init() {}
  }

  /// Streaming layout update
  public struct LayoutUpdate: Sendable {
    public let positions: [String: CGPoint]
    public let iteration: Int
    public let totalIterations: Int
    public var progress: Double { Double(iteration) / Double(totalIterations) }
    public let isComplete: Bool
  }

  /// Run force-directed layout with streaming updates
  public func computeForceLayout(
    nodes: [VisualNode],
    edges: [VisualEdge],
    canvasSize: CGSize,
    params: ForceLayoutParams = ForceLayoutParams()
  ) -> AsyncStream<LayoutUpdate> {
    AsyncStream { continuation in
      Task {
        // Initialize positions with static layout
        let staticLayout = computeLayout(nodes: nodes, edges: edges, canvasSize: canvasSize)
        var positions = staticLayout.nodePositions
        var velocities: [String: CGPoint] = [:]

        // Initialize velocities to zero
        for node in nodes {
          velocities[node.id] = .zero
          if positions[node.id] == nil {
            // Random position if not set
            positions[node.id] = CGPoint(
              x: CGFloat.random(in: 100...(canvasSize.width - 100)),
              y: CGFloat.random(in: 100...(canvasSize.height - 100))
            )
          }
        }

        // Build edge lookup
        let edgeLookup = Dictionary(grouping: edges) { $0.sourceId }

        // Simulation loop
        for iteration in 0..<params.maxIterations {
          var totalMovement: CGFloat = 0

          // Calculate forces
          var forces: [String: CGPoint] = [:]
          for node in nodes {
            forces[node.id] = .zero
          }

          // Repulsion forces (all pairs)
          for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
              let nodeA = nodes[i]
              let nodeB = nodes[j]

              guard let posA = positions[nodeA.id],
                let posB = positions[nodeB.id]
              else { continue }

              let dx = posB.x - posA.x
              let dy = posB.y - posA.y
              let distance = max(1, sqrt(dx * dx + dy * dy))

              // Coulomb's law: F = k / d^2
              let force = params.repulsionStrength / (distance * distance)
              let fx = (dx / distance) * force
              let fy = (dy / distance) * force

              forces[nodeA.id]?.x -= fx
              forces[nodeA.id]?.y -= fy
              forces[nodeB.id]?.x += fx
              forces[nodeB.id]?.y += fy
            }
          }

          // Attraction forces (edges)
          for node in nodes {
            guard let nodeEdges = edgeLookup[node.id] else { continue }

            for edge in nodeEdges {
              // Find target node
              guard
                let targetNode = nodes.first(where: {
                  "\($0.ecosystemId)::\($0.name)" == edge.targetId || $0.id == edge.targetId
                }),
                let sourcePos = positions[node.id],
                let targetPos = positions[targetNode.id]
              else { continue }

              let dx = targetPos.x - sourcePos.x
              let dy = targetPos.y - sourcePos.y
              let distance = sqrt(dx * dx + dy * dy)

              // Hooke's law: F = k * d
              let force = params.attractionStrength * distance
              let fx = (dx / max(1, distance)) * force
              let fy = (dy / max(1, distance)) * force

              forces[node.id]?.x += fx
              forces[node.id]?.y += fy
            }
          }

          // Center gravity
          let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
          for node in nodes {
            guard let pos = positions[node.id] else { continue }
            let dx = center.x - pos.x
            let dy = center.y - pos.y
            forces[node.id]?.x += dx * 0.001
            forces[node.id]?.y += dy * 0.001
          }

          // Apply forces
          for node in nodes {
            guard var velocity = velocities[node.id],
              var pos = positions[node.id],
              let force = forces[node.id]
            else { continue }

            // Update velocity with damping
            velocity.x = (velocity.x + force.x) * params.damping
            velocity.y = (velocity.y + force.y) * params.damping

            // Update position
            pos.x += velocity.x
            pos.y += velocity.y

            // Keep within bounds
            pos.x = max(50, min(canvasSize.width - 50, pos.x))
            pos.y = max(50, min(canvasSize.height - 50, pos.y))

            velocities[node.id] = velocity
            positions[node.id] = pos

            totalMovement += abs(velocity.x) + abs(velocity.y)
          }

          // Yield update every few iterations
          if iteration % 5 == 0 || iteration == params.maxIterations - 1 {
            let update = LayoutUpdate(
              positions: positions,
              iteration: iteration,
              totalIterations: params.maxIterations,
              isComplete: iteration == params.maxIterations - 1
            )
            continuation.yield(update)
          }

          // Check convergence
          let avgMovement = totalMovement / CGFloat(nodes.count)
          if avgMovement < params.convergenceThreshold {
            let finalUpdate = LayoutUpdate(
              positions: positions,
              iteration: iteration,
              totalIterations: params.maxIterations,
              isComplete: true
            )
            continuation.yield(finalUpdate)
            break
          }

          // Small delay to allow UI updates
          try? await Task.sleep(nanoseconds: 16_000_000)  // ~60fps
        }

        continuation.finish()
      }
    }
  }
}
