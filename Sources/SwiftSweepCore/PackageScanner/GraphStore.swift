import Foundation
import SQLite3

// MARK: - GraphStore Protocol

/// 图存储抽象接口 (支持未来升级到其他存储)
public protocol GraphStoreBackend: Sendable {
  /// 存储节点
  func insertNode(_ node: PackageNode) async throws

  /// 存储边
  func insertEdge(_ edge: DependencyEdge) async throws

  /// 批量存储节点
  func insertNodes(_ nodes: [PackageNode]) async throws

  /// 查询节点
  func getNode(by key: String) async throws -> PackageNode?

  /// 查询所有节点
  func getAllNodes() async throws -> [PackageNode]

  /// 查询依赖 (outgoing edges)
  func getDependencies(of key: String) async throws -> [PackageRef]

  /// 查询被依赖 (incoming edges)
  func getDependents(of key: String) async throws -> [PackageRef]

  /// 查询孤儿节点 (入度为 0 且非用户安装)
  func getOrphanNodes() async throws -> [PackageNode]

  /// 清空所有数据
  func clear() async throws
}

// MARK: - SQLiteGraphStore

/// 基于 SQLite 的图存储实现
public actor SQLiteGraphStore: GraphStoreBackend {

  private var db: OpaquePointer?
  private let path: String

  public init(path: String? = nil) {
    self.path = path ?? Self.defaultPath
  }

  private static var defaultPath: String {
    let supportDir = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let appDir = supportDir.appendingPathComponent("SwiftSweep", isDirectory: true)
    try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
    return appDir.appendingPathComponent("graph.sqlite").path
  }

  // MARK: - Database Setup

  public func open() throws {
    guard sqlite3_open(path, &db) == SQLITE_OK else {
      throw GraphStoreError.openFailed(errorMessage)
    }
    try createTables()
  }

  public func close() {
    sqlite3_close(db)
    db = nil
  }

  private func createTables() throws {
    let sql = """
      CREATE TABLE IF NOT EXISTS nodes (
          canonical_key TEXT PRIMARY KEY,
          logical_key TEXT NOT NULL,
          ecosystem_id TEXT NOT NULL,
          scope TEXT,
          name TEXT NOT NULL,
          version TEXT NOT NULL,
          fingerprint TEXT,
          install_path TEXT,
          size INTEGER,
          metadata_json TEXT,
          is_requested INTEGER DEFAULT 0,
          created_at INTEGER DEFAULT (strftime('%s', 'now'))
      );

      CREATE INDEX IF NOT EXISTS idx_nodes_ecosystem ON nodes(ecosystem_id);
      CREATE INDEX IF NOT EXISTS idx_nodes_logical ON nodes(logical_key);

      CREATE TABLE IF NOT EXISTS edges (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_key TEXT NOT NULL,
          target_ecosystem TEXT NOT NULL,
          target_scope TEXT,
          target_name TEXT NOT NULL,
          constraint_type TEXT,
          constraint_value TEXT,
          FOREIGN KEY (source_key) REFERENCES nodes(canonical_key)
      );

      CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_key);
      CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_ecosystem, target_name);
      """

    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw GraphStoreError.executeFailed(errorMessage)
    }
  }

  // MARK: - Insert Operations

  public func insertNode(_ node: PackageNode) async throws {
    let sql = """
      INSERT OR REPLACE INTO nodes 
      (canonical_key, logical_key, ecosystem_id, scope, name, version, fingerprint, install_path, size, metadata_json, is_requested)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      throw GraphStoreError.prepareFailed(errorMessage)
    }

    sqlite3_bind_text(stmt, 1, node.identity.canonicalKey, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 2, node.identity.logicalKey, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 3, node.identity.ecosystemId, -1, SQLITE_TRANSIENT)

    if let scope = node.identity.scope {
      sqlite3_bind_text(stmt, 4, scope, -1, SQLITE_TRANSIENT)
    } else {
      sqlite3_bind_null(stmt, 4)
    }

    sqlite3_bind_text(stmt, 5, node.identity.name, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 6, node.identity.version.normalized, -1, SQLITE_TRANSIENT)

    if let fp = node.identity.instanceFingerprint {
      sqlite3_bind_text(stmt, 7, fp, -1, SQLITE_TRANSIENT)
    } else {
      sqlite3_bind_null(stmt, 7)
    }

    if let path = node.metadata.installPath {
      sqlite3_bind_text(stmt, 8, path, -1, SQLITE_TRANSIENT)
    } else {
      sqlite3_bind_null(stmt, 8)
    }

    if let size = node.metadata.size {
      sqlite3_bind_int64(stmt, 9, size)
    } else {
      sqlite3_bind_null(stmt, 9)
    }

    // Serialize metadata to JSON
    if let metadataJson = try? JSONEncoder().encode(node.metadata) {
      sqlite3_bind_text(stmt, 10, String(data: metadataJson, encoding: .utf8), -1, SQLITE_TRANSIENT)
    } else {
      sqlite3_bind_null(stmt, 10)
    }

    sqlite3_bind_int(stmt, 11, 0)  // is_requested

    guard sqlite3_step(stmt) == SQLITE_DONE else {
      throw GraphStoreError.insertFailed(errorMessage)
    }
  }

  public func insertNodes(_ nodes: [PackageNode]) async throws {
    guard sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) == SQLITE_OK else {
      throw GraphStoreError.executeFailed(errorMessage)
    }

    do {
      for node in nodes {
        try await insertNode(node)
      }

      guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
        throw GraphStoreError.executeFailed(errorMessage)
      }
    } catch {
      sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
      throw error
    }
  }

  public func insertEdge(_ edge: DependencyEdge) async throws {
    let sql = """
      INSERT INTO edges (source_key, target_ecosystem, target_scope, target_name, constraint_type, constraint_value)
      VALUES (?, ?, ?, ?, ?, ?)
      """

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      throw GraphStoreError.prepareFailed(errorMessage)
    }

    sqlite3_bind_text(stmt, 1, edge.source.canonicalKey, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 2, edge.target.ecosystemId, -1, SQLITE_TRANSIENT)

    if let scope = edge.target.scope {
      sqlite3_bind_text(stmt, 3, scope, -1, SQLITE_TRANSIENT)
    } else {
      sqlite3_bind_null(stmt, 3)
    }

    sqlite3_bind_text(stmt, 4, edge.target.name, -1, SQLITE_TRANSIENT)

    switch edge.constraint {
    case .exact(let v):
      sqlite3_bind_text(stmt, 5, "exact", -1, SQLITE_TRANSIENT)
      sqlite3_bind_text(stmt, 6, v, -1, SQLITE_TRANSIENT)
    case .range(let r):
      sqlite3_bind_text(stmt, 5, "range", -1, SQLITE_TRANSIENT)
      sqlite3_bind_text(stmt, 6, r, -1, SQLITE_TRANSIENT)
    case .any:
      sqlite3_bind_text(stmt, 5, "any", -1, SQLITE_TRANSIENT)
      sqlite3_bind_null(stmt, 6)
    }

    guard sqlite3_step(stmt) == SQLITE_DONE else {
      throw GraphStoreError.insertFailed(errorMessage)
    }
  }

  // MARK: - Query Operations

  public func getNode(by key: String) async throws -> PackageNode? {
    let sql = "SELECT * FROM nodes WHERE canonical_key = ?"

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      throw GraphStoreError.prepareFailed(errorMessage)
    }

    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)

    if sqlite3_step(stmt) == SQLITE_ROW {
      return try parseNode(from: stmt)
    }

    return nil
  }

  public func getAllNodes() async throws -> [PackageNode] {
    let sql = "SELECT * FROM nodes ORDER BY ecosystem_id, name"

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      throw GraphStoreError.prepareFailed(errorMessage)
    }

    var nodes: [PackageNode] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      if let node = try? parseNode(from: stmt) {
        nodes.append(node)
      }
    }

    return nodes
  }

  public func getDependencies(of key: String) async throws -> [PackageRef] {
    let sql = "SELECT target_ecosystem, target_scope, target_name FROM edges WHERE source_key = ?"

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      throw GraphStoreError.prepareFailed(errorMessage)
    }

    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)

    var refs: [PackageRef] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      let ecosystem = String(cString: sqlite3_column_text(stmt, 0))
      let scope: String? =
        sqlite3_column_type(stmt, 1) == SQLITE_NULL
        ? nil : String(cString: sqlite3_column_text(stmt, 1))
      let name = String(cString: sqlite3_column_text(stmt, 2))
      refs.append(PackageRef(ecosystemId: ecosystem, scope: scope, name: name))
    }

    return refs
  }

  public func getDependents(of key: String) async throws -> [PackageRef] {
    // 先获取目标包信息
    guard let node = try await getNode(by: key) else { return [] }

    let sql = """
      SELECT n.ecosystem_id, n.scope, n.name 
      FROM edges e 
      JOIN nodes n ON e.source_key = n.canonical_key
      WHERE e.target_ecosystem = ? AND e.target_name = ?
      """

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      throw GraphStoreError.prepareFailed(errorMessage)
    }

    sqlite3_bind_text(stmt, 1, node.identity.ecosystemId, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 2, node.identity.name, -1, SQLITE_TRANSIENT)

    var refs: [PackageRef] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      let ecosystem = String(cString: sqlite3_column_text(stmt, 0))
      let scope: String? =
        sqlite3_column_type(stmt, 1) == SQLITE_NULL
        ? nil : String(cString: sqlite3_column_text(stmt, 1))
      let name = String(cString: sqlite3_column_text(stmt, 2))
      refs.append(PackageRef(ecosystemId: ecosystem, scope: scope, name: name))
    }

    return refs
  }

  public func getOrphanNodes() async throws -> [PackageNode] {
    // 孤儿节点：没有任何包依赖它且不是用户直接安装的
    let sql = """
      SELECT n.* FROM nodes n
      WHERE n.is_requested = 0
      AND NOT EXISTS (
          SELECT 1 FROM edges e 
          WHERE e.target_ecosystem = n.ecosystem_id 
          AND e.target_name = n.name
      )
      """

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      throw GraphStoreError.prepareFailed(errorMessage)
    }

    var nodes: [PackageNode] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      if let node = try? parseNode(from: stmt) {
        nodes.append(node)
      }
    }

    return nodes
  }

  /// Get full graph snapshot (nodes + valid edges) in single batch query
  public func getGraphSnapshot() async throws -> GraphSnapshot {
    let nodes = try await getAllNodes()
    let edges = try await getAllEdges()

    // Build a set of valid node keys for filtering
    let nodeKeys = Set(nodes.map { $0.identity.canonicalKey })

    // Filter to only edges where target exists as a node
    // (match by ecosystem + name, ignoring version differences)
    let nodeNameKeys = Set(nodes.map { "\($0.identity.ecosystemId)::\($0.identity.name)" })
    let validEdges = edges.filter { edge in
      let targetKey = "\(edge.target.ecosystemId)::\(edge.target.name)"
      return nodeNameKeys.contains(targetKey)
    }

    return GraphSnapshot(nodes: nodes, edges: validEdges)
  }

  /// Get all edges
  public func getAllEdges() async throws -> [DependencyEdge] {
    let sql = """
      SELECT e.source_key, e.target_ecosystem, e.target_scope, e.target_name, e.constraint_type, e.constraint_value,
             n.ecosystem_id, n.scope, n.name, n.version, n.fingerprint
      FROM edges e
      JOIN nodes n ON e.source_key = n.canonical_key
      ORDER BY e.source_key
      """

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      throw GraphStoreError.prepareFailed(errorMessage)
    }

    var edges: [DependencyEdge] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      // Parse source identity
      let sourceEcosystem = String(cString: sqlite3_column_text(stmt, 6))
      let sourceScope: String? =
        sqlite3_column_type(stmt, 7) == SQLITE_NULL
        ? nil : String(cString: sqlite3_column_text(stmt, 7))
      let sourceName = String(cString: sqlite3_column_text(stmt, 8))
      let sourceVersionStr = String(cString: sqlite3_column_text(stmt, 9))
      let sourceFingerprint: String? =
        sqlite3_column_type(stmt, 10) == SQLITE_NULL
        ? nil : String(cString: sqlite3_column_text(stmt, 10))

      let sourceVersion: ResolvedVersion =
        sourceVersionStr == "unknown" ? .unknown : .exact(sourceVersionStr)
      let sourceIdentity = PackageIdentity(
        ecosystemId: sourceEcosystem,
        scope: sourceScope,
        name: sourceName,
        version: sourceVersion,
        instanceFingerprint: sourceFingerprint
      )

      // Parse target ref
      let targetEcosystem = String(cString: sqlite3_column_text(stmt, 1))
      let targetScope: String? =
        sqlite3_column_type(stmt, 2) == SQLITE_NULL
        ? nil : String(cString: sqlite3_column_text(stmt, 2))
      let targetName = String(cString: sqlite3_column_text(stmt, 3))
      let targetRef = PackageRef(ecosystemId: targetEcosystem, scope: targetScope, name: targetName)

      // Parse constraint
      let constraintType: String? =
        sqlite3_column_type(stmt, 4) == SQLITE_NULL
        ? nil : String(cString: sqlite3_column_text(stmt, 4))
      let constraintValue: String? =
        sqlite3_column_type(stmt, 5) == SQLITE_NULL
        ? nil : String(cString: sqlite3_column_text(stmt, 5))

      let constraint: VersionConstraint
      switch constraintType {
      case "exact": constraint = .exact(constraintValue ?? "")
      case "range": constraint = .range(constraintValue ?? "")
      default: constraint = .any
      }

      edges.append(
        DependencyEdge(source: sourceIdentity, target: targetRef, constraint: constraint))
    }

    return edges
  }

  public func clear() async throws {
    let sql = "DELETE FROM edges; DELETE FROM nodes;"
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw GraphStoreError.executeFailed(errorMessage)
    }
  }

  // MARK: - Helpers

  private func parseNode(from stmt: OpaquePointer?) throws -> PackageNode {
    guard let stmt = stmt else {
      throw GraphStoreError.parseFailed("Null statement")
    }

    let ecosystemId = String(cString: sqlite3_column_text(stmt, 2))
    let scope: String? =
      sqlite3_column_type(stmt, 3) == SQLITE_NULL
      ? nil : String(cString: sqlite3_column_text(stmt, 3))
    let name = String(cString: sqlite3_column_text(stmt, 4))
    let versionStr = String(cString: sqlite3_column_text(stmt, 5))
    let fingerprint: String? =
      sqlite3_column_type(stmt, 6) == SQLITE_NULL
      ? nil : String(cString: sqlite3_column_text(stmt, 6))

    let version: ResolvedVersion = versionStr == "unknown" ? .unknown : .exact(versionStr)

    let identity = PackageIdentity(
      ecosystemId: ecosystemId,
      scope: scope,
      name: name,
      version: version,
      instanceFingerprint: fingerprint
    )

    let installPath: String? =
      sqlite3_column_type(stmt, 7) == SQLITE_NULL
      ? nil : String(cString: sqlite3_column_text(stmt, 7))
    let size: Int64? =
      sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 8)

    let metadata = PackageMetadata(installPath: installPath, size: size)

    return PackageNode(identity: identity, metadata: metadata)
  }

  private var errorMessage: String {
    String(cString: sqlite3_errmsg(db))
  }
}

// MARK: - Errors

public enum GraphStoreError: Error, LocalizedError {
  case openFailed(String)
  case prepareFailed(String)
  case executeFailed(String)
  case insertFailed(String)
  case parseFailed(String)

  public var errorDescription: String? {
    switch self {
    case .openFailed(let msg): return "Failed to open database: \(msg)"
    case .prepareFailed(let msg): return "Failed to prepare statement: \(msg)"
    case .executeFailed(let msg): return "Failed to execute: \(msg)"
    case .insertFailed(let msg): return "Failed to insert: \(msg)"
    case .parseFailed(let msg): return "Failed to parse: \(msg)"
    }
  }
}

// MARK: - SQLITE_TRANSIENT

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - GraphSnapshot

/// Complete graph snapshot for visualization
public struct GraphSnapshot: Sendable {
  public let nodes: [PackageNode]
  public let edges: [DependencyEdge]

  public var nodeCount: Int { nodes.count }
  public var edgeCount: Int { edges.count }
}
