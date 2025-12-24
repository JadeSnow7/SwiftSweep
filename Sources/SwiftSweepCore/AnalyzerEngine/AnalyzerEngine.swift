import Foundation

// MARK: - iCloud Status

/// iCloud 文件下载状态
public enum ICloudStatus: String, Sendable {
  case local = "local"  // 本地文件（非 iCloud）
  case downloaded = "downloaded"  // iCloud 文件，已下载到本地
  case cloudOnly = "cloudOnly"  // iCloud 文件，仅在云端（占位符）
  case downloading = "downloading"  // 正在下载中
}

// MARK: - FileNode (Recursive Tree Structure)

/// Represents a node in the file system tree (file or directory)
public final class FileNode: Identifiable, Hashable, @unchecked Sendable {
  public let id = UUID()
  public let name: String
  public let path: String
  public let isDirectory: Bool
  public private(set) var size: Int64  // 逻辑大小（表观大小）
  public private(set) var children: [FileNode]?
  public weak var parent: FileNode?

  /// iCloud 文件状态
  public let iCloudStatus: ICloudStatus

  /// Number of files in this subtree (including self if file)
  public private(set) var fileCount: Int
  /// Number of directories in this subtree (including self if directory)
  public private(set) var dirCount: Int

  /// 子树中仅在云端的文件数量
  public private(set) var cloudOnlyCount: Int

  /// 本地文件体积（排除仅在云端的文件）
  public private(set) var localSize: Int64

  /// 实际磁盘占用（物理大小，考虑稀疏文件）
  public private(set) var physicalSize: Int64

  public init(
    name: String, path: String, isDirectory: Bool, size: Int64 = 0,
    physicalSize: Int64? = nil, iCloudStatus: ICloudStatus = .local
  ) {
    self.name = name
    self.path = path
    self.isDirectory = isDirectory
    self.size = size
    self.physicalSize = physicalSize ?? size  // 默认等于逻辑大小
    self.iCloudStatus = iCloudStatus
    self.children = isDirectory ? [] : nil
    self.fileCount = isDirectory ? 0 : 1
    self.dirCount = isDirectory ? 1 : 0
    self.cloudOnlyCount = (iCloudStatus == .cloudOnly && !isDirectory) ? 1 : 0
    // 本地大小：如果是仅在云端的文件则为0，否则为实际大小
    self.localSize = (iCloudStatus == .cloudOnly) ? 0 : size
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
    physicalSize += child.physicalSize
    localSize += child.localSize
    fileCount += child.fileCount
    dirCount += child.dirCount
    cloudOnlyCount += child.cloudOnlyCount
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

    // iCloud 相关的 URL 资源键
    let resourceKeys: [URLResourceKey] = [
      .isDirectoryKey,
      .fileSizeKey,
      .isUbiquitousItemKey,
      .ubiquitousItemDownloadingStatusKey,
      .ubiquitousItemIsDownloadingKey,
    ]

    var scannedCount = 0
    var lastUIUpdate = Date()

    /// 检测 iCloud 文件状态
    func getICloudStatus(for url: URL) -> ICloudStatus {
      guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else {
        return .local
      }

      // 检查是否为 iCloud 项目
      guard values.isUbiquitousItem == true else {
        return .local
      }

      // 检查是否正在下载
      if values.ubiquitousItemIsDownloading == true {
        return .downloading
      }

      // 检查下载状态
      if let downloadStatus = values.ubiquitousItemDownloadingStatus {
        switch downloadStatus {
        case .current:
          return .downloaded
        case .downloaded:
          return .downloaded
        case .notDownloaded:
          return .cloudOnly
        default:
          return .local
        }
      }

      return .local
    }

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
        // 可能是仅在云端的文件（占位符）
        let iCloudStatus = getICloudStatus(for: url)
        if iCloudStatus == .cloudOnly {
          // 尝试获取云端文件大小
          let size =
            (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
          return FileNode(
            name: name, path: nodePath, isDirectory: false, size: size,
            physicalSize: 0, iCloudStatus: .cloudOnly)  // 云端文件物理大小为0
        }
        return FileNode(name: name, path: nodePath, isDirectory: false, size: 0)
      }

      if !isDir.boolValue {
        // It's a file - 获取逻辑大小和物理大小
        let logicalSize =
          (try? fileManager.attributesOfItem(atPath: nodePath)[.size] as? Int64) ?? 0

        // 获取物理大小（实际磁盘占用）
        let physicalSize: Int64
        if let allocatedSize = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
          .totalFileAllocatedSize
        {
          physicalSize = Int64(allocatedSize)
        } else {
          // Fallback: 使用 stat 获取块大小
          var statInfo = stat()
          if stat(nodePath, &statInfo) == 0 {
            physicalSize = Int64(statInfo.st_blocks) * 512  // st_blocks 以 512 字节块为单位
          } else {
            physicalSize = logicalSize  // 无法获取时使用逻辑大小
          }
        }

        let iCloudStatus = getICloudStatus(for: url)
        scannedCount += 1

        // Throttle progress updates
        if Date().timeIntervalSince(lastUIUpdate) > 0.2 {
          lastUIUpdate = Date()
          onProgress?(scannedCount, 0)  // Size will be computed after tree is built
        }

        return FileNode(
          name: name, path: nodePath, isDirectory: false, size: logicalSize,
          physicalSize: physicalSize, iCloudStatus: iCloudStatus)
      }

      // It's a directory
      let dirNode = FileNode(name: name, path: nodePath, isDirectory: true)

      guard
        let contents = try? fileManager.contentsOfDirectory(
          at: url, includingPropertiesForKeys: resourceKeys,
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
  public func analyze(
    path: String, includeHiddenFiles: Bool = false, onProgress: ((Int, Int64) -> Void)? = nil
  ) async throws
    -> AnalysisResult
  {
    let root = try await buildTree(
      path: path, includeHiddenFiles: includeHiddenFiles, onProgress: onProgress)

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
