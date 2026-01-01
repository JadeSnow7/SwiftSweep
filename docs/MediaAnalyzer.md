# MediaAnalyzer 使用指南

媒体文件智能分析模块，用于检测相似/重复的图片和视频。

---

## 快速开始

### 1. 请求目录访问权限

```swift
import SwiftSweepCore

// 用户选择目录
let url = await MediaScanner.shared.requestDirectoryAccess()

// 保存书签以便后续访问
try? await MediaScanner.shared.saveBookmark(for: url)
```

### 2. 执行分析

```swift
let result = try await MediaAnalyzer.shared.analyze(
    root: url,
    onPhase: { phase in
        print("Phase: \(phase.rawValue)")
    },
    onProgress: { current, total in
        print("Progress: \(current)/\(total)")
    }
)

print("Files: \(result.scanResult.files.count)")
print("Similar groups: \(result.similarGroups.count)")
print("Reclaimable: \(result.totalReclaimableSize) bytes")
```

### 3. 快速扫描（不计算哈希）

```swift
let scanResult = await MediaAnalyzer.shared.quickScan(root: url)
```

---

## 核心 API

### MediaAnalyzer

```swift
public actor MediaAnalyzer {
    /// 完整分析
    func analyze(root: URL, onPhase:, onProgress:) async throws -> MediaAnalysisResult
    
    /// 快速扫描
    func quickScan(root: URL, onProgress:) async -> MediaScanResult
}
```

### MediaScanner

```swift
public actor MediaScanner {
    /// 请求目录访问
    func requestDirectoryAccess() async -> URL?
    
    /// 保存安全作用域书签
    func saveBookmark(for url: URL) throws
    
    /// 扫描目录
    func scan(root: URL, onProgress:) async -> MediaScanResult
}
```

### PerceptualHasher

```swift
public struct PerceptualHasher {
    /// 计算视频 pHash
    func hashVideo(url: URL, sampleCount: Int) async throws -> UInt64
    
    /// 计算图片 pHash
    func hashImage(url: URL) async throws -> UInt64
    
    /// 汉明距离
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int
    
    /// 相似度阈值（默认 10）
    static let similarityThreshold = 10
}
```

---

## 数据结构

### MediaFile

```swift
public struct MediaFile: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let type: MediaType        // .video, .image, .audio
    let size: Int64
    let duration: Double?      // 视频时长
    let resolution: CGSize?    // 分辨率
    let perceptualHash: UInt64?
}
```

### SimilarGroup

```swift
public struct SimilarGroup: Identifiable, Sendable {
    let id: UUID
    let representative: MediaFile  // 保留的文件（最大）
    let duplicates: [MediaFile]    // 可删除的文件
    let totalSize: Int64
    let reclaimableSize: Int64     // 可回收空间
}
```

---

## 支持的格式

| 类型 | 格式 |
|-----|-----|
| 视频 | mp4, mov, m4v, avi, mkv, webm, wmv, flv, 3gp |
| 图片 | jpg, jpeg, png, heic, gif, webp, bmp, tiff |
| 音频 | mp3, m4a, aac, wav, flac, aiff, ogg |

---

## 性能优化

- **缓存**: pHash 结果持久化到 SQLite，基于 inode+mtime 失效
- **增量扫描**: 只计算新增/修改文件的哈希
- **并发**: 使用 ConcurrentScheduler 限制并发数

---

## UI 集成

使用 `MediaAnalyzerView`:

```swift
import SwiftSweepUI

struct ContentView: View {
    var body: some View {
        MediaAnalyzerView()
    }
}
```

