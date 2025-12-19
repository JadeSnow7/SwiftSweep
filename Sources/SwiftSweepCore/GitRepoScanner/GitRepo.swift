import Foundation

// MARK: - GitRepo Model

/// Represents a Git repository found on the system
public struct GitRepo: Identifiable, Sendable, Equatable {
  public let id: String  // Absolute path (unique identifier)
  public let name: String  // Directory name
  public let path: String  // Absolute path to repo root
  public let gitDir: String  // Path to .git directory (resolved for worktrees)

  // Loaded async
  public var isDirty: Bool?
  public var gitDirSize: Int64?

  public init(name: String, path: String, gitDir: String) {
    self.id = path
    self.name = name
    self.path = path
    self.gitDir = gitDir
    self.isDirty = nil
    self.gitDirSize = nil
  }

  public static func == (lhs: GitRepo, rhs: GitRepo) -> Bool {
    lhs.id == rhs.id
  }
}

// MARK: - Scan Result

/// Result of a Git repository scan
public struct GitRepoScanResult: Sendable {
  public let repos: [GitRepo]
  public let scanDuration: TimeInterval
  public let scannedPaths: [String]
  public let error: String?

  public init(
    repos: [GitRepo], scanDuration: TimeInterval, scannedPaths: [String], error: String? = nil
  ) {
    self.repos = repos
    self.scanDuration = scanDuration
    self.scannedPaths = scannedPaths
    self.error = error
  }
}
