import Foundation

#if canImport(SwiftSweepCore)
  // Internal file, no need to import self
#endif

/// Service for managing package graph snapshots
public actor SnapshotService {
  public static let shared = SnapshotService()

  private let graphService = DependencyGraphService.shared
  private let store: SQLiteGraphStore

  public init(store: SQLiteGraphStore = SQLiteGraphStore()) {
    self.store = store
  }

  // MARK: - Export

  /// Capture current state as a snapshot
  public func exportSnapshot(version: String = "1.0") async throws -> PackageSnapshot {
    let nodes = try await graphService.getAllNodes()

    // Heuristic: "Requested" packages are those with in-degree == 0 (no incoming edges)
    // We need to query dependencies to build the graph structure for this heuristic
    var inDegrees: [String: Int] = [:]

    // Initialize standard packages
    for node in nodes {
      inDegrees[node.identity.canonicalKey] = 0
    }

    for node in nodes {
      let deps = try await graphService.getDependencies(of: node)
      for dep in deps {
        // Construct canonical key for dependency
        let key: String
        if let scope = dep.scope {
          key = "\(dep.ecosystemId)::\(scope)/\(dep.name)"
        } else {
          key = "\(dep.ecosystemId)::\(dep.name)"
        }
        // Note: graphService.getDependencies returns PackageRef which might not perfectly match
        // canonicalKey logic if scope isn't handled identical to PackageIdentity,
        // but let's assume standard format matches.

        // Simpler approach: Use store directly via graphService if possible, or just build
        // in-memory graph from all edges if there was a way to get all edges efficiently.
        // Actually, we can use graphService.getGraphSnapshot() for efficiency!
        inDegrees[key, default: 0] += 1
      }
    }

    // Better approach: Use the new Batch Query API from Phase A/4
    let graphSnapshot = try await graphService.getGraphSnapshot()

    // Reset inDegrees from the accurate snapshot
    inDegrees.removeAll()
    for node in graphSnapshot.nodes {
      inDegrees[node.id] = 0
    }
    for edge in graphSnapshot.edges {
      inDegrees[edge.target.key, default: 0] += 1
    }

    // Classify packages
    var requested: [SnapshotPackageRef] = []
    var transitive: [SnapshotPackageRef] = []

    // We need to map VisualNode/GraphSnapshot data back to PackageIdentity info
    // or assume we have enough info in nodes to reconstruct.
    // GraphSnapshot nodes lack version info (VisualNode is for UI).
    // So we iterate the original full nodes list.

    for node in nodes {
      let ref = SnapshotPackageRef(
        ecosystem: node.identity.ecosystemId,
        name: node.identity.name,
        version: node.identity.version.normalized,
        scope: node.identity.scope
      )

      let key = node.identity.canonicalKey
      if (inDegrees[key] ?? 0) == 0 {
        requested.append(ref)
      } else {
        transitive.append(ref)
      }
    }

    // Context
    let processInfo = ProcessInfo.processInfo
    let context = SnapshotContext(
      arch: getMachineArchitecture() ?? "unknown",
      os: "macos",  // Simplified for now
      hostname: processInfo.hostName
    )

    return PackageSnapshot(
      version: version,
      timestamp: Date(),
      machineId: getMachineUUID() ?? "unknown",
      context: context,
      manifest: SnapshotManifest(requested: requested, transitive: transitive)
    )
  }

  public func exportToFile(snapshot: PackageSnapshot, url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted

    let data = try encoder.encode(snapshot)
    try data.write(to: url)
  }

  // MARK: - Import

  public func importFromFile(url: URL) throws -> PackageSnapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let data = try Data(contentsOf: url)
    return try decoder.decode(PackageSnapshot.self, from: data)
  }

  // MARK: - Diff

  public func compareSnapshot(current: PackageSnapshot, baseline: PackageSnapshot) -> SnapshotDiff {
    // Combine requested + transitive for full comparison
    let currentPackages = current.manifest.requested + current.manifest.transitive
    let baselinePackages = baseline.manifest.requested + baseline.manifest.transitive

    // Map by ID (ecosystem + name + scope) excludes version
    // Key format: ecosystem::[scope/]name
    func makeKey(_ p: SnapshotPackageRef) -> String {
      if let scope = p.scope {
        return "\(p.ecosystem)::\(scope)/\(p.name)"
      }
      return "\(p.ecosystem)::\(p.name)"
    }

    let currentMap = Dictionary(uniqueKeysWithValues: currentPackages.map { (makeKey($0), $0) })
    let baselineMap = Dictionary(uniqueKeysWithValues: baselinePackages.map { (makeKey($0), $0) })

    var added: [SnapshotPackageRef] = []
    var removed: [SnapshotPackageRef] = []
    var changed: [(old: SnapshotPackageRef, new: SnapshotPackageRef)] = []

    // Find added and changed
    for (key, currentPkg) in currentMap {
      if let baselinePkg = baselineMap[key] {
        if currentPkg.version != baselinePkg.version {
          changed.append((old: baselinePkg, new: currentPkg))
        }
      } else {
        added.append(currentPkg)
      }
    }

    // Find removed
    for (key, baselinePkg) in baselineMap {
      if currentMap[key] == nil {
        removed.append(baselinePkg)
      }
    }

    return SnapshotDiff(added: added, removed: removed, changed: changed)
  }

  // MARK: - Private Helpers

  private func getMachineArchitecture() -> String? {
    #if arch(x86_64)
      return "x86_64"
    #elseif arch(arm64)
      return "arm64"
    #else
      return nil
    #endif
  }

  private func getMachineUUID() -> String? {
    // In a real app, use IOKit to get hardware UUID
    // For sandboxed app, maybe use a generated UUID stored in defaults
    return UserDefaults.standard.string(forKey: "OneSweepMachineUUID")
      ?? {
        let uuid = UUID().uuidString
        UserDefaults.standard.set(uuid, forKey: "OneSweepMachineUUID")
        return uuid
      }()
  }
}
