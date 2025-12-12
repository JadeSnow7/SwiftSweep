import Foundation

/// SwiftSweep 磁盘分析引擎 - 扫描大文件和目录统计
public final class AnalyzerEngine {
    public static let shared = AnalyzerEngine()
    
    private init() {}
    
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
    
    public struct AnalysisResult {
        public let topFiles: [FileItem]
        public let totalSize: Int64
        public let fileCount: Int
        public let dirCount: Int
        
        public init(topFiles: [FileItem], totalSize: Int64, fileCount: Int, dirCount: Int) {
            self.topFiles = topFiles
            self.totalSize = totalSize
            self.fileCount = fileCount
            self.dirCount = dirCount
        }
    }
    
    // 跳过的系统目录
    private let skipDirs = [
        ".Trash", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100",
        "node_modules", ".git", "Library/Caches", ".npm", ".gradle"
    ]
    
    /// 执行磁盘分析
    /// - Parameters:
    ///   - path: 目标路径
    ///   - onProgress: 进度回调 (已扫描文件数, 当前总大小)
    /// - Returns: 分析结果
    public func analyze(path: String, onProgress: ((Int, Int64) -> Void)? = nil) async throws -> AnalysisResult {
        let fileManager = FileManager.default
        var allFiles: [FileItem] = []
        var fileCount = 0
        var dirCount = 0
        var totalSize: Int64 = 0
        var lastUIUpdate = Date()
        
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return AnalysisResult(topFiles: [], totalSize: 0, fileCount: 0, dirCount: 0)
        }
        
        // 使用 while 循环而非 for-in
        while let fileURL = enumerator.nextObject() as? URL {
            // 检查取消状态 (通过 Task.isCancelled)
            if Task.isCancelled { break }
            
            // 跳过特定目录
            let pathStr = fileURL.path
            if skipDirs.contains(where: { pathStr.contains($0) }) {
                enumerator.skipDescendants()
                continue
            }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey])
                
                if resourceValues.isDirectory == true {
                    dirCount += 1
                } else if resourceValues.isRegularFile == true {
                    fileCount += 1
                    let size = Int64(resourceValues.fileSize ?? 0)
                    totalSize += size
                    
                    // 只保存大于1MB的文件用于排序，减少内存占用
                    if size > 1_000_000 {
                        allFiles.append(FileItem(path: pathStr, size: size))
                    }
                }
            } catch {
                continue
            }
            
            // 节流回调
            if Date().timeIntervalSince(lastUIUpdate) > 0.3 {
                lastUIUpdate = Date()
                onProgress?(fileCount, totalSize)
            }
        }
        
        // 最终排序
        let sorted = allFiles.sorted { $0.size > $1.size }.prefix(20)
        
        return AnalysisResult(
            topFiles: Array(sorted),
            totalSize: totalSize,
            fileCount: fileCount,
            dirCount: dirCount
        )
    }
}
