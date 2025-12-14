import Foundation

/// Disk Analyzer for Mac App Store version (read-only, sandboxed)
public final class AnalyzerEngine: @unchecked Sendable {
    public static let shared = AnalyzerEngine()
    
    private init() {}
    
    // Directories to skip for performance
    private let skipDirs: Set<String> = [
        ".Trash", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100",
        "node_modules", ".git", ".npm", ".gradle", ".cache"
    ]
    
    /// Analysis constraints for Extension context
    public struct AnalysisLimits {
        public var maxDepth: Int = 5
        public var maxItems: Int = 10_000
        public var timeout: TimeInterval = 10
        
        public static let `default` = AnalysisLimits()
        public static let quick = AnalysisLimits(maxDepth: 3, maxItems: 1_000, timeout: 3)
    }
    
    /// Backward-compatible FileItem
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
    
    /// Analysis result
    public struct AnalysisResult {
        public let topFiles: [FileItem]
        public let totalSize: Int64
        public let fileCount: Int
        public let dirCount: Int
        public let rootNode: FileNode?
        public let wasLimited: Bool  // True if hit limits
        
        public init(topFiles: [FileItem], totalSize: Int64, fileCount: Int, dirCount: Int, 
                    rootNode: FileNode? = nil, wasLimited: Bool = false) {
            self.topFiles = topFiles
            self.totalSize = totalSize
            self.fileCount = fileCount
            self.dirCount = dirCount
            self.rootNode = rootNode
            self.wasLimited = wasLimited
        }
    }
    
    /// Quick summary for notification display
    public struct QuickSummary {
        public let totalSize: String
        public let fileCount: Int
        public let dirCount: Int
        public let largestItem: (name: String, size: String)?
        public let wasLimited: Bool
    }
    
    // MARK: - Analysis
    
    /// Perform disk analysis with limits
    public func analyze(
        path: String,
        limits: AnalysisLimits = .default,
        onProgress: ((Int, Int64) -> Void)? = nil
    ) async throws -> AnalysisResult {
        
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: path)
        let deadline = Date().addingTimeInterval(limits.timeout)
        
        var scannedCount = 0
        var hitLimit = false
        var lastUIUpdate = Date()
        
        // Recursive function to build tree
        func scanDirectory(_ url: URL, depth: Int) -> FileNode? {
            // Check limits
            if Date() > deadline { hitLimit = true; return nil }
            if scannedCount >= limits.maxItems { hitLimit = true; return nil }
            if depth > limits.maxDepth { return nil }
            if Task.isCancelled { return nil }
            
            let name = url.lastPathComponent
            let nodePath = url.path
            
            // Skip certain directories
            if skipDirs.contains(name) {
                return FileNode(name: name, path: nodePath, isDirectory: true, size: 0)
            }
            
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: nodePath, isDirectory: &isDir) else {
                return nil
            }
            
            if !isDir.boolValue {
                // It's a file
                let size = (try? fileManager.attributesOfItem(atPath: nodePath)[.size] as? Int64) ?? 0
                scannedCount += 1
                
                // Throttle progress updates
                if Date().timeIntervalSince(lastUIUpdate) > 0.2 {
                    lastUIUpdate = Date()
                    onProgress?(scannedCount, 0)
                }
                
                return FileNode(name: name, path: nodePath, isDirectory: false, size: size)
            }
            
            // It's a directory
            let dirNode = FileNode(name: name, path: nodePath, isDirectory: true)
            
            guard let contents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return dirNode
            }
            
            // Process children
            for childURL in contents {
                if let childNode = scanDirectory(childURL, depth: depth + 1) {
                    dirNode.addChild(childNode)
                }
            }
            
            return dirNode
        }
        
        guard let root = scanDirectory(rootURL, depth: 0) else {
            return AnalysisResult(
                topFiles: [],
                totalSize: 0,
                fileCount: 0,
                dirCount: 0,
                wasLimited: hitLimit
            )
        }
        
        root.sortChildrenBySize()
        
        // Final progress update
        onProgress?(root.fileCount, root.size)
        
        let largestFiles = root.getLargestFiles(limit: 20)
        let topFiles = largestFiles.map { 
            FileItem(path: $0.path, size: $0.size, isDirectory: false) 
        }
        
        return AnalysisResult(
            topFiles: topFiles,
            totalSize: root.size,
            fileCount: root.fileCount,
            dirCount: root.dirCount,
            rootNode: root,
            wasLimited: hitLimit
        )
    }
    
    /// Get quick summary for notification
    public func quickSummary(path: String) async throws -> QuickSummary {
        let result = try await analyze(path: path, limits: .quick)
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        
        return QuickSummary(
            totalSize: formatter.string(fromByteCount: result.totalSize),
            fileCount: result.fileCount,
            dirCount: result.dirCount,
            largestItem: result.topFiles.first.map {
                ($0.path.components(separatedBy: "/").last ?? "",
                 formatter.string(fromByteCount: $0.size))
            },
            wasLimited: result.wasLimited
        )
    }
}

// MARK: - Errors

public enum AnalyzerError: Error, LocalizedError {
    case accessDenied(String)
    case analysisTimeout
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .accessDenied(let reason): return reason
        case .analysisTimeout: return "Analysis timed out"
        case .cancelled: return "Analysis was cancelled"
        }
    }
}
