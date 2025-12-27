import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

// MARK: - Visual Models for Galaxy View

/// Visual representation of a package node in the galaxy
public struct VisualNode: Identifiable, Sendable {
  public let id: String
  public let identity: PackageIdentity
  public let ecosystemId: String
  public let name: String
  public let displayName: String
  public let size: Int64?

  // Layout properties
  public var position: CGPoint
  public var radius: CGFloat
  public var color: Color

  // State
  public var isSelected: Bool
  public var isHovered: Bool

  public init(from node: PackageNode, position: CGPoint = .zero) {
    self.id = node.identity.canonicalKey
    self.identity = node.identity
    self.ecosystemId = node.identity.ecosystemId
    self.name = node.identity.name
    self.displayName =
      node.identity.scope.map { "\($0)/\(node.identity.name)" } ?? node.identity.name
    self.size = node.metadata.size
    self.position = position
    self.radius = Self.computeRadius(size: node.metadata.size)
    self.color = Self.ecosystemColor(node.identity.ecosystemId)
    self.isSelected = false
    self.isHovered = false
  }

  // Size-based radius: log scale, clamped to 6-18pt
  private static func computeRadius(size: Int64?) -> CGFloat {
    guard let size = size, size > 0 else { return 10 }
    let logSize = log10(Double(size))
    // Map log(1KB=3) to log(1GB=9) -> 6 to 18
    let normalized = (logSize - 3) / 6  // 0 to 1 for 1KB to 1GB
    let clamped = max(0, min(1, normalized))
    return 6 + CGFloat(clamped) * 12
  }

  // Ecosystem colors
  private static func ecosystemColor(_ ecosystemId: String) -> Color {
    switch ecosystemId {
    case "homebrew_formula": return .orange
    case "homebrew_cask": return .purple
    case "npm": return .green
    case "pip": return .blue
    case "gem": return .red
    default: return .gray
    }
  }
}

/// Visual representation of a dependency edge
public struct VisualEdge: Identifiable, Sendable {
  public let id: String
  public let sourceId: String
  public let targetId: String
  public let sourceEcosystem: String
  public var sourcePosition: CGPoint
  public var targetPosition: CGPoint

  public init(from edge: DependencyEdge, sourcePos: CGPoint = .zero, targetPos: CGPoint = .zero) {
    self.id = "\(edge.source.canonicalKey)->\(edge.target.key)"
    self.sourceId = edge.source.canonicalKey
    self.targetId = edge.target.key
    self.sourceEcosystem = edge.source.ecosystemId
    self.sourcePosition = sourcePos
    self.targetPosition = targetPos
  }

  /// Edge color based on source ecosystem
  public var color: Color {
    switch sourceEcosystem {
    case "homebrew_formula": return .orange
    case "homebrew_cask": return .purple
    case "npm": return .green
    case "pip": return .blue
    case "gem": return .red
    default: return .gray
    }
  }
}

/// Cluster information for LOD rendering
public struct ClusterInfo: Identifiable, Sendable {
  public let id: String
  public let ecosystemId: String
  public let displayName: String
  public let nodeCount: Int
  public let totalSize: Int64
  public var position: CGPoint
  public var radius: CGFloat
  public var color: Color

  public init(ecosystemId: String, nodes: [VisualNode]) {
    self.id = "cluster_\(ecosystemId)"
    self.ecosystemId = ecosystemId
    self.displayName = Self.displayName(for: ecosystemId)
    self.nodeCount = nodes.count
    self.totalSize = nodes.compactMap { $0.size }.reduce(0, +)
    self.position = .zero
    self.radius = CGFloat(min(50, 20 + nodes.count / 5))
    self.color = nodes.first?.color ?? .gray
  }

  private static func displayName(for id: String) -> String {
    switch id {
    case "homebrew_formula": return "Homebrew"
    case "homebrew_cask": return "Cask"
    case "npm": return "npm"
    case "pip": return "Python"
    case "gem": return "Ruby"
    default: return id
    }
  }
}

// MARK: - Layout Result

/// Result of layout computation
public struct LayoutResult: Sendable {
  public let nodePositions: [String: CGPoint]
  public let clusterPositions: [String: CGPoint]

  public init(nodePositions: [String: CGPoint] = [:], clusterPositions: [String: CGPoint] = [:]) {
    self.nodePositions = nodePositions
    self.clusterPositions = clusterPositions
  }
}

// MARK: - LOD Level

/// Level of Detail for rendering
public enum LODLevel: Sendable {
  case cluster  // < 20% zoom: only cluster dots
  case overview  // 20-60%: top 50 nodes + clusters
  case detail  // > 60%: all visible nodes

  public init(zoomScale: CGFloat) {
    switch zoomScale {
    case ..<0.2: self = .cluster
    case 0.2..<0.6: self = .overview
    default: self = .detail
    }
  }
}
