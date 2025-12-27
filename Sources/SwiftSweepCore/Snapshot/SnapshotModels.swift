import Foundation

/// Represents a full snapshot of the package dependency graph state
public struct PackageSnapshot: Codable, Sendable {
  public let version: String
  public let timestamp: Date
  public let machineId: String
  public let context: SnapshotContext
  public let manifest: SnapshotManifest

  public init(
    version: String = "1.0",
    timestamp: Date = Date(),
    machineId: String,
    context: SnapshotContext,
    manifest: SnapshotManifest
  ) {
    self.version = version
    self.timestamp = timestamp
    self.machineId = machineId
    self.context = context
    self.manifest = manifest
  }
}

/// Context about the environment where the snapshot was taken
public struct SnapshotContext: Codable, Sendable {
  public let arch: String
  public let os: String
  public let hostname: String

  public init(arch: String, os: String, hostname: String) {
    self.arch = arch
    self.os = os
    self.hostname = hostname
  }
}

/// The lists of packages in the snapshot
public struct SnapshotManifest: Codable, Sendable {
  public let requested: [SnapshotPackageRef]  // Inferred roots (in-degree == 0)
  public let transitive: [SnapshotPackageRef]  // Dependencies (in-degree > 0)

  public init(requested: [SnapshotPackageRef], transitive: [SnapshotPackageRef]) {
    self.requested = requested
    self.transitive = transitive
  }
}

/// Reference to a package in a snapshot
/// Renamed to avoid specific conflict with core PackageRef if it exists,
/// though effectively serves similar purpose for the snapshot context.
public struct SnapshotPackageRef: Codable, Sendable, Identifiable, Hashable {
  public let ecosystem: String
  public let name: String
  public let version: String
  public let scope: String?

  public var id: String {
    if let scope = scope {
      return "\(ecosystem)::\(scope)/\(name)"
    }
    return "\(ecosystem)::\(name)"
  }

  public var displayName: String {
    if let scope = scope {
      return "\(scope)/\(name)"
    }
    return name
  }

  public init(ecosystem: String, name: String, version: String, scope: String?) {
    self.ecosystem = ecosystem
    self.name = name
    self.version = version
    self.scope = scope
  }
}

/// Result of comparing two snapshots
public struct SnapshotDiff: Sendable {
  public let added: [SnapshotPackageRef]
  public let removed: [SnapshotPackageRef]
  public let changed: [(old: SnapshotPackageRef, new: SnapshotPackageRef)]  // Version changes
}
