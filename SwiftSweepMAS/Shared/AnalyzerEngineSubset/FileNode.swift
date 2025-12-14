import Foundation

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
