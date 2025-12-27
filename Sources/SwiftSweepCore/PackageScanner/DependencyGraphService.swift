import Foundation

// MARK: - DependencyGraphService

/// 依赖图服务 - 协调采集、存储和查询
public actor DependencyGraphService {

  public static let shared = DependencyGraphService()

  private let store: SQLiteGraphStore
  private var providers: [any PackageMetadataProvider] = []
  private var isInitialized = false

  public init(store: SQLiteGraphStore = SQLiteGraphStore()) {
    self.store = store
  }

  // MARK: - Setup

  /// 初始化服务
  public func initialize() async throws {
    guard !isInitialized else { return }

    try await store.open()

    // 注册默认 providers
    let normalizer = createNormalizer()
    providers = [
      BrewJsonProvider(normalizer: normalizer),
      NpmJsonProvider(normalizer: normalizer),
      PipMetadataProvider(normalizer: normalizer),
    ]

    isInitialized = true
  }

  private func createNormalizer() -> PathNormalizer {
    // Determine brew prefix based on which path exists (no blocking Process call)
    let brewPrefix: String?
    if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
      brewPrefix = "/opt/homebrew"
    } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
      brewPrefix = "/usr/local"
    } else {
      brewPrefix = nil
    }

    return PathNormalizer(brewPrefix: brewPrefix)
  }

  // MARK: - Scanning

  /// 扫描所有 provider 并构建图
  public func scanAll() async -> DependencyGraphResult {
    var allNodes: [PackageNode] = []
    var allEdges: [DependencyEdge] = []
    var errors: [IngestionError] = []

    for provider in providers {
      let result = await provider.fetchInstalledRecords()

      // 处理错误
      errors.append(contentsOf: result.errors)

      // 转换 records 为 nodes
      for record in result.records {
        let metadata: PackageMetadata

        // 尝试解析为 Brew 特定元数据以获取 size 和 dependencies
        if let brewMeta = try? JSONDecoder().decode(BrewPackageMetadata.self, from: record.rawJSON)
        {
          metadata = PackageMetadata(
            installPath: brewMeta.installPath,
            size: brewMeta.size,
            description: brewMeta.description,
            homepage: brewMeta.homepage,
            license: brewMeta.license
          )
          // Brew dependencies are simple names (no scope)
          for dep in brewMeta.dependencies {
            allEdges.append(
              DependencyEdge(
                source: record.identity,
                target: PackageRef(ecosystemId: result.ecosystemId, scope: nil, name: dep),
                constraint: .any
              ))
          }
        } else if let npmMeta = try? JSONDecoder().decode(
          NpmPackageMetadata.self, from: record.rawJSON)
        {
          metadata = PackageMetadata(
            installPath: npmMeta.installPath,
            size: npmMeta.size
          )
          // npm dependencies may have scope (@types/react -> scope: @types, name: react)
          for dep in npmMeta.dependencies {
            let (scope, name) = Self.parseNpmPackageName(dep)
            allEdges.append(
              DependencyEdge(
                source: record.identity,
                target: PackageRef(ecosystemId: result.ecosystemId, scope: scope, name: name),
                constraint: .any
              ))
          }
        } else if let pipMeta = try? JSONDecoder().decode(
          PipPackageMetadata.self, from: record.rawJSON)
        {
          metadata = PackageMetadata(
            installPath: pipMeta.installPath,
            size: pipMeta.size,
            description: pipMeta.summary
          )
          // pip dependencies
          for dep in pipMeta.requiresDist {
            allEdges.append(
              DependencyEdge(
                source: record.identity,
                target: PackageRef(ecosystemId: result.ecosystemId, scope: nil, name: dep),
                constraint: .any
              ))
          }
        } else {
          metadata = PackageMetadata()
        }

        let node = PackageNode(identity: record.identity, metadata: metadata)
        allNodes.append(node)
      }
    }

    // 存储到 GraphStore
    do {
      try await store.clear()
      try await store.insertNodes(allNodes)
      for edge in allEdges {
        try await store.insertEdge(edge)
      }
    } catch {
      errors.append(
        IngestionError(phase: "store", message: error.localizedDescription, recoverable: false))
    }

    return DependencyGraphResult(
      nodeCount: allNodes.count,
      edgeCount: allEdges.count,
      errors: errors
    )
  }

  // MARK: - Queries

  /// 获取所有节点
  public func getAllNodes() async throws -> [PackageNode] {
    try await store.getAllNodes()
  }

  /// 获取节点的依赖
  public func getDependencies(of node: PackageNode) async throws -> [PackageRef] {
    try await store.getDependencies(of: node.identity.canonicalKey)
  }

  /// 获取依赖该节点的包
  public func getDependents(of node: PackageNode) async throws -> [PackageRef] {
    try await store.getDependents(of: node.identity.canonicalKey)
  }

  /// 获取孤儿节点 (Ghost Buster)
  public func getOrphanNodes() async throws -> [PackageNode] {
    try await store.getOrphanNodes()
  }

  /// 模拟删除影响
  public func simulateRemoval(of node: PackageNode) async throws -> RemovalImpact {
    let dependents = try await getDependents(of: node)

    // 递归获取所有受影响的包
    var affected: Set<String> = []
    var queue = dependents.map { $0.key }

    while let key = queue.first {
      queue.removeFirst()
      if affected.contains(key) { continue }
      affected.insert(key)

      // 获取这个包的 dependents
      if let depNode = try await store.getNode(by: key) {
        let moreDeps = try await store.getDependents(of: depNode.identity.canonicalKey)
        queue.append(contentsOf: moreDeps.map { $0.key })
      }
    }

    return RemovalImpact(
      directDependents: dependents,
      totalAffected: affected.count,
      isSafeToRemove: affected.isEmpty
    )
  }

  // MARK: - Graph Snapshot

  /// Get full graph snapshot for visualization
  public func getGraphSnapshot() async throws -> GraphSnapshot {
    try await store.getGraphSnapshot()
  }

  // MARK: - Statistics

  /// 获取图统计
  public func getStatistics() async throws -> GraphStatistics {
    let allNodes = try await store.getAllNodes()
    let orphans = try await store.getOrphanNodes()

    var byEcosystem: [String: Int] = [:]
    var totalSize: Int64 = 0

    for node in allNodes {
      byEcosystem[node.identity.ecosystemId, default: 0] += 1
      if let size = node.metadata.size {
        totalSize += size
      }
    }

    return GraphStatistics(
      totalNodes: allNodes.count,
      orphanCount: orphans.count,
      byEcosystem: byEcosystem,
      totalSize: totalSize
    )
  }

  // MARK: - Helpers

  /// Parse npm package name with scope (e.g., @types/react -> scope: @types, name: react)
  private static func parseNpmPackageName(_ fullName: String) -> (scope: String?, name: String) {
    if fullName.hasPrefix("@") {
      let parts = fullName.split(separator: "/", maxSplits: 1)
      if parts.count == 2 {
        return (String(parts[0]), String(parts[1]))
      }
    }
    return (nil, fullName)
  }
}

// MARK: - Result Types

/// 扫描结果
public struct DependencyGraphResult: Sendable {
  public let nodeCount: Int
  public let edgeCount: Int
  public let errors: [IngestionError]

  public var isSuccess: Bool { errors.isEmpty }
  public var isPartial: Bool { !errors.isEmpty && nodeCount > 0 }
}

/// 删除影响分析
public struct RemovalImpact: Sendable {
  public let directDependents: [PackageRef]
  public let totalAffected: Int
  public let isSafeToRemove: Bool
}

/// 图统计
public struct GraphStatistics: Sendable {
  public let totalNodes: Int
  public let orphanCount: Int
  public let byEcosystem: [String: Int]
  public let totalSize: Int64
}
