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
}
