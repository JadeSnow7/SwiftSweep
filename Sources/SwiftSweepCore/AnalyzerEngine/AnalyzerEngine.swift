import Foundation

// MARK: - FileNode (Recursive Tree Structure)

/// Represents a node in the file system tree (file or directory)
public final class FileNode: Identifiable, Hashable, @unchecked Sendable {
  public let id = UUID()
  public let name: String
  public let path: String
  public let isDirectory: Bool
  public private(set) var size: Int64
  public private(set) var children: [FileNode]?
  public weak var parent: FileNode?

  /// Number of files in this subtree (including self if file)
  public private(set) var fileCount: Int
  /// Number of directories in this subtree (including self if directory)
  public private(set) var dirCount: Int

  public init(name: String, path: String, isDirectory: Bool, size: Int64 = 0) {
    self.name = name
    self.path = path
    self.isDirectory = isDirectory
    self.size = size
    self.children = isDirectory ? [] : nil
    self.fileCount = isDirectory ? 0 : 1
    self.dirCount = isDirectory ? 1 : 0
  }

  public static func == (lhs: FileNode, rhs: FileNode) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  /// Add a child node and update size/counts
  public func addChild(_ child: FileNode) {
    child.parent = self
    children?.append(child)
    size += child.size
    fileCount += child.fileCount
    dirCount += child.dirCount
  }

  /// Sort children by size descending (largest first)
  public func sortChildrenBySize() {
    children?.sort { $0.size > $1.size }
    children?.forEach { $0.sortChildrenBySize() }
  }

  /// Get flat list of largest files in subtree
  public func getLargestFiles(limit: Int = 20) -> [FileNode] {
    var files: [FileNode] = []
    collectFiles(into: &files)
    return Array(files.sorted { $0.size > $1.size }.prefix(limit))
  }

  private func collectFiles(into array: inout [FileNode]) {
    if !isDirectory {
      array.append(self)
    } else {
      children?.forEach { $0.collectFiles(into: &array) }
    }
  }
}

// MARK: - AnalyzerEngine

/// SwiftSweep Disk Analyzer - Builds hierarchical file tree with size aggregation
public final class AnalyzerEngine: @unchecked Sendable {
  public static let shared = AnalyzerEngine()

  private init() {}

  // Directories to skip for performance
  private let skipDirs: Set<String> = [
    ".Trash", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100",
    "node_modules", ".git", ".npm", ".gradle", ".cache",
  ]

  /// Backward-compatible FileItem for existing UI
  public struct FileItem: Identifiable, Hashable {
    public let id = UUID()
    public let path: String
    public let size: Int64
    public let isDirectory: Bool

    public init(path: String, size: Int64, isDirectory: Bool = false) {
      self.path = path
      self.size = size
      self.isDirectory = isDirectory
    }
  }

  /// Backward-compatible AnalysisResult
  public struct AnalysisResult {
    public let topFiles: [FileItem]
    public let totalSize: Int64
    public let fileCount: Int
    public let dirCount: Int

    /// New: Full tree structure
    public let rootNode: FileNode?

    public init(
      topFiles: [FileItem], totalSize: Int64, fileCount: Int, dirCount: Int,
      rootNode: FileNode? = nil
    ) {
      self.topFiles = topFiles
      self.totalSize = totalSize
      self.fileCount = fileCount
      self.dirCount = dirCount
      self.rootNode = rootNode
    }
  }

  // MARK: - Tree-based Analysis (New)

  /// Build complete file tree with size aggregation
  /// - Parameters:
  ///   - path: Root path to analyze
  ///   - includeHiddenFiles: Whether to include hidden files (default: false)
  ///   - onProgress: Progress callback (scanned items, current total size)
  /// - Returns: Root FileNode of the tree
  public func buildTree(
    path: String, includeHiddenFiles: Bool = false, onProgress: ((Int, Int64) -> Void)? = nil
  ) async throws
    -> FileNode
  {
    let fileManager = FileManager.default
    let rootURL = URL(fileURLWithPath: path)
    let skipHidden = !includeHiddenFiles

    var scannedCount = 0
    var lastUIUpdate = Date()

    // Recursive function to build tree
    func scanDirectory(_ url: URL) -> FileNode {
      let name = url.lastPathComponent
      let nodePath = url.path

      // Check if should skip
      if skipDirs.contains(name) {
        return FileNode(name: name, path: nodePath, isDirectory: true, size: 0)
      }

      var isDir: ObjCBool = false
      guard fileManager.fileExists(atPath: nodePath, isDirectory: &isDir) else {
        return FileNode(name: name, path: nodePath, isDirectory: false, size: 0)
      }

      if !isDir.boolValue {
        // It's a file
        let size = (try? fileManager.attributesOfItem(atPath: nodePath)[.size] as? Int64) ?? 0
        scannedCount += 1

        // Throttle progress updates
        if Date().timeIntervalSince(lastUIUpdate) > 0.2 {
          lastUIUpdate = Date()
          onProgress?(scannedCount, 0)  // Size will be computed after tree is built
        }

        return FileNode(name: name, path: nodePath, isDirectory: false, size: size)
      }

      // It's a directory
      let dirNode = FileNode(name: name, path: nodePath, isDirectory: true)

      guard
        let contents = try? fileManager.contentsOfDirectory(
          at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
          options: skipHidden ? [.skipsHiddenFiles] : [])
      else {
        return dirNode
      }

      // Process children
      for childURL in contents {
        if Task.isCancelled { break }
        let childNode = scanDirectory(childURL)
        dirNode.addChild(childNode)
      }

      return dirNode
    }

    let root = scanDirectory(rootURL)
    root.sortChildrenBySize()

    // Final progress update
    onProgress?(root.fileCount, root.size)

    return root
  }

  // MARK: - Backward Compatible Analysis

  /// Perform disk analysis (backward compatible, now uses tree internally)
  public func analyze(path: String, includeHiddenFiles: Bool = false, onProgress: ((Int, Int64) -> Void)? = nil) async throws
    -> AnalysisResult
  {
    let root = try await buildTree(path: path, includeHiddenFiles: includeHiddenFiles, onProgress: onProgress)

    let largestFiles = root.getLargestFiles(limit: 20)
    let topFiles = largestFiles.map { FileItem(path: $0.path, size: $0.size, isDirectory: false) }

    return AnalysisResult(
      topFiles: topFiles,
      totalSize: root.size,
      fileCount: root.fileCount,
      dirCount: root.dirCount,
      rootNode: root
    )
  }
}
