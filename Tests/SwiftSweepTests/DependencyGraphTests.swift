import XCTest

@testable import SwiftSweepCore

final class DependencyGraphTests: XCTestCase {

  var store: SQLiteGraphStore!
  var testDbPath: String!

  override func setUp() async throws {
    // 使用临时数据库
    testDbPath = NSTemporaryDirectory() + "test_graph_\(UUID().uuidString).sqlite"
    store = SQLiteGraphStore(path: testDbPath)
    try await store.open()
  }

  override func tearDown() async throws {
    await store.close()
    try? FileManager.default.removeItem(atPath: testDbPath)
  }

  // MARK: - GraphStore Tests

  func testInsertAndRetrieveNode() async throws {
    let identity = PackageIdentity(
      ecosystemId: "homebrew_formula",
      scope: "homebrew/core",
      name: "openssl",
      version: .exact("3.1.4"),
      instanceFingerprint: "abc123"
    )

    let metadata = PackageMetadata(
      installPath: "/opt/homebrew/Cellar/openssl/3.1.4", size: 10_000_000)
    let node = PackageNode(identity: identity, metadata: metadata)

    try await store.insertNode(node)

    let retrieved = try await store.getNode(by: identity.canonicalKey)
    XCTAssertNotNil(retrieved)
    XCTAssertEqual(retrieved?.identity.name, "openssl")
    XCTAssertEqual(retrieved?.identity.version.normalized, "3.1.4")
    XCTAssertEqual(retrieved?.metadata.size, 10_000_000)
  }

  func testBatchInsertNodes() async throws {
    let nodes = (1...10).map { i in
      PackageNode(
        identity: PackageIdentity(
          ecosystemId: "npm",
          scope: nil,
          name: "package-\(i)",
          version: .exact("1.0.\(i)"),
          instanceFingerprint: nil
        ),
        metadata: PackageMetadata()
      )
    }

    try await store.insertNodes(nodes)

    let allNodes = try await store.getAllNodes()
    XCTAssertEqual(allNodes.count, 10)
  }

  func testInsertAndQueryEdges() async throws {
    // 创建两个节点
    let nodeA = PackageNode(
      identity: PackageIdentity(
        ecosystemId: "homebrew_formula", name: "wget", version: .exact("1.21")),
      metadata: PackageMetadata()
    )
    let nodeB = PackageNode(
      identity: PackageIdentity(
        ecosystemId: "homebrew_formula", name: "openssl", version: .exact("3.0")),
      metadata: PackageMetadata()
    )

    try await store.insertNode(nodeA)
    try await store.insertNode(nodeB)

    // 创建边: wget -> openssl
    let edge = DependencyEdge(
      source: nodeA.identity,
      target: PackageRef(ecosystemId: "homebrew_formula", name: "openssl"),
      constraint: .any
    )

    try await store.insertEdge(edge)

    // 查询 wget 的依赖
    let deps = try await store.getDependencies(of: nodeA.identity.canonicalKey)
    XCTAssertEqual(deps.count, 1)
    XCTAssertEqual(deps.first?.name, "openssl")
  }

  func testGetDependents() async throws {
    // 创建节点: A depends on B
    let nodeA = PackageNode(
      identity: PackageIdentity(ecosystemId: "npm", name: "react-app", version: .exact("1.0")),
      metadata: PackageMetadata()
    )
    let nodeB = PackageNode(
      identity: PackageIdentity(ecosystemId: "npm", name: "react", version: .exact("18.0")),
      metadata: PackageMetadata()
    )

    try await store.insertNodes([nodeA, nodeB])

    let edge = DependencyEdge(
      source: nodeA.identity,
      target: PackageRef(ecosystemId: "npm", name: "react"),
      constraint: .range("^18.0")
    )
    try await store.insertEdge(edge)

    // 查询 react 的被依赖者
    let dependents = try await store.getDependents(of: nodeB.identity.canonicalKey)
    XCTAssertEqual(dependents.count, 1)
    XCTAssertEqual(dependents.first?.name, "react-app")
  }

  func testOrphanNodeDetection() async throws {
    // nodeA: 被 nodeB 依赖 (非孤儿)
    // nodeB: 依赖 nodeA (非孤儿，因为是"主包")
    // nodeC: 无任何依赖关系 (孤儿)

    let nodeA = PackageNode(
      identity: PackageIdentity(ecosystemId: "pip", name: "numpy", version: .exact("1.24")),
      metadata: PackageMetadata()
    )
    let nodeB = PackageNode(
      identity: PackageIdentity(ecosystemId: "pip", name: "pandas", version: .exact("2.0")),
      metadata: PackageMetadata()
    )
    let nodeC = PackageNode(
      identity: PackageIdentity(ecosystemId: "pip", name: "orphan-pkg", version: .exact("0.1")),
      metadata: PackageMetadata()
    )

    try await store.insertNodes([nodeA, nodeB, nodeC])

    // pandas -> numpy
    try await store.insertEdge(
      DependencyEdge(
        source: nodeB.identity,
        target: PackageRef(ecosystemId: "pip", name: "numpy"),
        constraint: .any
      ))

    let orphans = try await store.getOrphanNodes()

    // orphan-pkg 应该被识别为孤儿 (入度=0)
    // numpy 不是孤儿 (被 pandas 依赖)
    // pandas 不是孤儿 (虽然没人依赖它，但 is_requested 逻辑)
    XCTAssertTrue(orphans.contains { $0.identity.name == "orphan-pkg" })
  }

  func testClearStore() async throws {
    let node = PackageNode(
      identity: PackageIdentity(ecosystemId: "gem", name: "rails", version: .exact("7.0")),
      metadata: PackageMetadata()
    )

    try await store.insertNode(node)
    let nodes1 = try await store.getAllNodes(); XCTAssertEqual(nodes1.count, 1)

    try await store.clear()
    let nodes0 = try await store.getAllNodes(); XCTAssertEqual(nodes0.count, 0)
  }

  // MARK: - PackageIdentity Integration

  func testLogicalKeyStability() {
    let id1 = PackageIdentity(
      ecosystemId: "npm", scope: "@types", name: "react", version: .exact("18.0"))
    let id2 = PackageIdentity(
      ecosystemId: "npm", scope: "@types", name: "react", version: .exact("18.0"))

    XCTAssertEqual(id1.logicalKey, id2.logicalKey)
  }

  func testCanonicalKeyDiffersByFingerprint() {
    let id1 = PackageIdentity(
      ecosystemId: "pip", name: "numpy", version: .exact("1.24"), instanceFingerprint: "fp1")
    let id2 = PackageIdentity(
      ecosystemId: "pip", name: "numpy", version: .exact("1.24"), instanceFingerprint: "fp2")

    XCTAssertEqual(id1.logicalKey, id2.logicalKey)
    XCTAssertNotEqual(id1.canonicalKey, id2.canonicalKey)
  }
}
