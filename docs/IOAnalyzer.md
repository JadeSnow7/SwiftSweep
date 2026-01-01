# IOAnalyzer 使用指南

I/O 性能分析模块，用于监控和优化磁盘 I/O 性能。

---

## 快速开始

### 1. 开始分析

```swift
import SwiftSweepCore

// 开始追踪
await IOAnalyzer.shared.startAnalysis(aggregationInterval: 1.0) { slice in
    print("Read: \(slice.readThroughput) B/s")
    print("Write: \(slice.writeThroughput) B/s")
}
```

### 2. 获取分析结果

```swift
let result = await IOAnalyzer.shared.getAnalysisResult()

print("Total Read: \(result.totalReadBytes) bytes")
print("Total Write: \(result.totalWriteBytes) bytes")
print("Optimizations: \(result.optimizations.count)")
```

### 3. 停止分析

```swift
await IOAnalyzer.shared.stopAnalysis()
```

---

## 核心 API

### IOAnalyzer

```swift
public actor IOAnalyzer {
    /// 开始分析
    func startAnalysis(aggregationInterval:, onSlice:) async
    
    /// 停止分析
    func stopAnalysis() async
    
    /// 获取分析结果
    func getAnalysisResult() async -> IOAnalysisResult
    
    /// 设置采样率 (0.0 - 1.0)
    func setSampleRate(_ rate: Double) async
}
```

### IOSelfTracer

```swift
public actor IOSelfTracer {
    /// 追踪的文件读取
    func trackedRead(at url: URL) async throws -> Data
    
    /// 追踪的文件写入
    func trackedWrite(_ data: Data, to url: URL) async throws
    
    /// 追踪的目录遍历
    func trackedContents(at url: URL) async throws -> [URL]
}
```

---

## 数据结构

### IOTimeSlice

```swift
public struct IOTimeSlice: Sendable {
    let startTime: Date
    let duration: TimeInterval
    let readBytes: Int64
    let writeBytes: Int64
    let readOps: Int
    let writeOps: Int
    let avgLatencyNanos: UInt64
    let p99LatencyNanos: UInt64
    
    var readThroughput: Double   // bytes/sec
    var writeThroughput: Double  // bytes/sec
}
```

### IOOptimization

```swift
public struct IOOptimization: Sendable {
    let type: IOHotspotType
    let severity: Severity       // .low, .medium, .high
    let suggestion: String
    let estimatedImprovement: String
}
```

### IOHotspotType

```swift
public enum IOHotspotType {
    case frequentSmallReads(path: String, avgSize: Int64)
    case highLatency(path: String, avgLatencyMs: Double)
    case heavyWrite(path: String, bytesPerSec: Double)
    case fragmentedAccess(path: String, opsPerSec: Double)
}
```

---

## 使用追踪包装器

IOAnalyzer 自动追踪使用 `trackedXXX` 方法的操作：

```swift
// 追踪读取
let data = try await IOAnalyzer.shared.trackedRead(at: fileURL)

// 追踪写入
try await IOAnalyzer.shared.trackedWrite(data, to: outputURL)

// 追踪目录遍历
let contents = try await IOAnalyzer.shared.trackedContents(at: directoryURL)
```

---

## 配置选项

### 采样率

降低采样率以减少开销：

```swift
await IOAnalyzer.shared.setSampleRate(0.5)  // 50% 采样
```

### 缓冲区统计

监控缓冲区状态：

```swift
let stats = await IOAnalyzer.shared.getBufferStats()
print("Events: \(stats.count)")
print("Drop rate: \(stats.dropRate * 100)%")
```

---

## UI 集成

使用 `IOAnalyzerView`:

```swift
import SwiftSweepUI

struct ContentView: View {
    var body: some View {
        IOAnalyzerView()
    }
}
```

---

## 设计原则

1. **无特权**: 仅监控自身 I/O，无需 root 或 entitlement
2. **沙盒兼容**: 适用于 App Store 版本
3. **低开销**: 环形缓冲区 + 采样率控制
4. **隐私保护**: 路径自动脱敏

