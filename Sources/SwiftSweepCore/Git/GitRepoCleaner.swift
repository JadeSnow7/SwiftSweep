import Foundation

// MARK: - Git Repo Cleaner

/// Cleans build artifacts and redundant files from Git repositories
public actor GitRepoCleaner {
  public static let shared = GitRepoCleaner()

  private let fileManager = FileManager.default
  private let runner: ProcessRunner

  private init() {
    self.runner = ProcessRunner()
  }

  // MARK: - Cleanup Patterns

  /// Common build artifact patterns to clean
  public static let buildArtifactPatterns: [String] = [
    ".build",  // Swift Package Manager
    "build",  // Xcode build folder
    "DerivedData",  // Xcode derived data
    "*.xcarchive",  // Xcode archives
    "node_modules",  // npm packages
    "dist",  // Distribution builds
    "target",  // Rust/Maven builds
    "__pycache__",  // Python cache
    "*.pyc",  // Python compiled
    ".gradle",  // Gradle cache
    ".pytest_cache",  // pytest cache
    ".tox",  // tox environments
    "venv",  // Python virtual env
    "env",  // Generic env folder
  ]

  /// Redundant file patterns
  public static let redundantFilePatterns: [String] = [
    ".DS_Store",  // macOS metadata
    "._*",  // AppleDouble files
    "Thumbs.db",  // Windows thumbnails
    "*.log",  // Log files
    "*.swp",  // Vim swap files
    "*~",  // Backup files
    ".*.swp",  // Hidden swap files
  ]

  // MARK: - Scan Result

  public struct CleanupItem: Identifiable {
    public let id = UUID()
    public let path: String
    public let size: Int64
    public let type: CleanupType

    public enum CleanupType: String {
      case buildArtifact = "Build Artifact"
      case redundantFile = "Redundant File"
      case gitObject = "Git Object"
    }
  }

  public struct CleanupResult {
    public let items: [CleanupItem]
    public let totalSize: Int64
    public let repoPath: String

    public init(items: [CleanupItem], totalSize: Int64, repoPath: String) {
      self.items = items
      self.totalSize = totalSize
      self.repoPath = repoPath
    }
  }

  // MARK: - Scan

  /// Scan a Git repository for cleanable items
  public func scan(repoPath: String) async -> CleanupResult {
    var items: [CleanupItem] = []

    // Scan for build artifacts
    items.append(contentsOf: await scanBuildArtifacts(in: repoPath))

    // Scan for redundant files
    items.append(contentsOf: await scanRedundantFiles(in: repoPath))

    // Scan for Git-specific cleanup opportunities
    items.append(contentsOf: await scanGitObjects(in: repoPath))

    let totalSize = items.reduce(0) { $0 + $1.size }

    return CleanupResult(items: items, totalSize: totalSize, repoPath: repoPath)
  }

  // MARK: - Clean

  /// Remove specified cleanup items
  public func clean(items: [CleanupItem]) async throws -> Int64 {
    var totalCleaned: Int64 = 0

    for item in items {
      do {
        let size = item.size
        try fileManager.removeItem(atPath: item.path)
        totalCleaned += size
      } catch {
        // Log error but continue with other items
        print("Failed to remove \(item.path): \(error)")
      }
    }

    return totalCleaned
  }

  /// Run git gc to optimize repository
  public func runGitGC(repoPath: String, aggressive: Bool = false) async -> (
    success: Bool, message: String
  ) {
    guard let gitURL = findGit() else {
      return (false, "git command not found")
    }

    let args =
      aggressive
      ? ["-C", repoPath, "gc", "--aggressive", "--prune=now"]
      : ["-C", repoPath, "gc", "--auto"]

    let result = await runner.run(
      executable: gitURL.path,
      arguments: args,
      environment: ToolLocator.packageFinderEnvironment
    )

    if result.exitCode == 0 {
      let output = String(data: result.stdout, encoding: .utf8) ?? ""
      return (true, output.isEmpty ? "Git GC completed successfully" : output)
    } else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
      return (false, stderr)
    }
  }

  /// Run git prune to remove unreachable objects
  public func runGitPrune(repoPath: String) async -> (success: Bool, message: String) {
    guard let gitURL = findGit() else {
      return (false, "git command not found")
    }

    let result = await runner.run(
      executable: gitURL.path,
      arguments: ["-C", repoPath, "prune"],
      environment: ToolLocator.packageFinderEnvironment
    )

    if result.exitCode == 0 {
      return (true, "Git prune completed successfully")
    } else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
      return (false, stderr)
    }
  }

  // MARK: - Private Scanning Methods

  private func scanBuildArtifacts(in repoPath: String) async -> [CleanupItem] {
    var items: [CleanupItem] = []

    guard
      let enumerator = fileManager.enumerator(
        at: URL(fileURLWithPath: repoPath),
        includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    while let fileURL = enumerator.nextObject() as? URL {
      let relativePath = fileURL.path.replacingOccurrences(of: repoPath + "/", with: "")

      // Skip .git directory
      if relativePath.hasPrefix(".git/") || relativePath == ".git" {
        enumerator.skipDescendants()
        continue
      }

      // Check if matches build artifact pattern
      for pattern in Self.buildArtifactPatterns {
        if matchesPattern(relativePath, pattern: pattern) {
          if let size = calculateSize(at: fileURL.path) {
            items.append(
              CleanupItem(
                path: fileURL.path,
                size: size,
                type: .buildArtifact
              ))
          }
          enumerator.skipDescendants()
          break
        }
      }
    }

    return items
  }

  private func scanRedundantFiles(in repoPath: String) async -> [CleanupItem] {
    var items: [CleanupItem] = []

    guard
      let enumerator = fileManager.enumerator(
        at: URL(fileURLWithPath: repoPath),
        includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
        options: []
      )
    else {
      return []
    }

    while let fileURL = enumerator.nextObject() as? URL {
      let relativePath = fileURL.path.replacingOccurrences(of: repoPath + "/", with: "")
      let fileName = fileURL.lastPathComponent

      // Skip .git directory
      if relativePath.hasPrefix(".git/") || relativePath == ".git" {
        enumerator.skipDescendants()
        continue
      }

      // Check if matches redundant file pattern
      for pattern in Self.redundantFilePatterns {
        if matchesPattern(fileName, pattern: pattern) {
          if let size = calculateSize(at: fileURL.path) {
            items.append(
              CleanupItem(
                path: fileURL.path,
                size: size,
                type: .redundantFile
              ))
          }
          break
        }
      }
    }

    return items
  }

  private func scanGitObjects(in repoPath: String) async -> [CleanupItem] {
    var items: [CleanupItem] = []

    let gitDir = repoPath + "/.git"

    // Check for AppleDouble files in pack directory
    let packDir = gitDir + "/objects/pack"
    if fileManager.fileExists(atPath: packDir) {
      if let contents = try? fileManager.contentsOfDirectory(atPath: packDir) {
        for file in contents where file.hasPrefix("._") {
          let filePath = packDir + "/" + file
          if let size = calculateSize(at: filePath) {
            items.append(
              CleanupItem(
                path: filePath,
                size: size,
                type: .gitObject
              ))
          }
        }
      }
    }

    return items
  }

  // MARK: - Helper Methods

  private func matchesPattern(_ string: String, pattern: String) -> Bool {
    if pattern.contains("*") {
      // Simple wildcard matching
      let regexPattern =
        pattern
        .replacingOccurrences(of: ".", with: "\\.")
        .replacingOccurrences(of: "*", with: ".*")

      if let regex = try? NSRegularExpression(pattern: "^" + regexPattern + "$") {
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, range: range) != nil
      }
    }

    return string == pattern
  }

  private func calculateSize(at path: String) -> Int64? {
    var isDir: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else {
      return nil
    }

    if isDir.boolValue {
      // Calculate directory size
      var totalSize: Int64 = 0
      if let enumerator = fileManager.enumerator(atPath: path) {
        for case let file as String in enumerator {
          let filePath = path + "/" + file
          if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
            let size = attrs[.size] as? Int64
          {
            totalSize += size
          }
        }
      }
      return totalSize
    } else {
      // File size
      if let attrs = try? fileManager.attributesOfItem(atPath: path),
        let size = attrs[.size] as? Int64
      {
        return size
      }
    }

    return nil
  }

  private func findGit() -> URL? {
    ToolLocator.find("git")
  }
}
