# SwiftSweep 架构文档

## 概述

SwiftSweep 是一个 macOS 磁盘清理和优化工具，采用模块化架构设计。

---

## 模块架构

```
SwiftSweepCore/
├── AnalyzerEngine/       # 磁盘分析
├── CleanupEngine/        # 清理执行
├── RecommendationEngine/ # 智能建议
├── MediaAnalyzer/        # 媒体分析 ⭐ NEW
├── IOAnalyzer/           # I/O 分析 ⭐ NEW
├── Shared/               # 共享组件
│   ├── PerformanceMonitor.swift
│   └── ConcurrentScheduler.swift
└── ...

SwiftSweepUI/
├── MediaAnalyzerView.swift  ⭐ NEW
├── IOAnalyzerView.swift     ⭐ NEW
└── ...
```

---

## 核心组件

### 1. MediaAnalyzer - 媒体智能分析

**职责**: 检测相似/重复的图片和视频

```
┌─────────────────┐
│  MediaScanner   │ → 扫描目录，获取媒体文件
└────────┬────────┘
         ↓
┌─────────────────┐     ┌────────────┐
│PerceptualHasher │ ←→  │ pHashCache │ SQLite 缓存
└────────┬────────┘     └────────────┘
         ↓
┌─────────────────┐
│SimilarityDetector│ → LSH 加速 + Union-Find 聚类
└────────┬────────┘
         ↓
┌─────────────────┐
│  MediaAnalyzer  │ → 主入口编排器
└─────────────────┘
```

**关键算法**:
- **pHash**: DCT 变换取低频分量，生成 64-bit 哈希
- **LSH**: 4 band × 16 bits，将 O(n²) 优化为 O(n)
- **缓存**: inode + mtime 作为失效键

---

### 2. IOAnalyzer - I/O 性能分析

**职责**: 监控 I/O 性能，检测热点和瓶颈

```
┌─────────────────┐
│  IOSelfTracer   │ → 自身 I/O 追踪（沙盒兼容）
└────────┬────────┘
         ↓
┌─────────────────┐
│  IOEventBuffer  │ → 环形缓冲区 + 采样控制
└────────┬────────┘
         ↓
┌─────────────────┐
│  IOAggregator   │ → 时间片聚合 + P99 延迟
└────────┬────────┘
         ↓
┌─────────────────┐
│IOHotspotDetector│ → 热点检测 + 优化建议
└─────────────────┘
```

**关键设计**:
- **无特权**: 仅监控自身 I/O，无需 root
- **背压控制**: 环形缓冲区 + 采样率动态调整
- **隐私保护**: 路径脱敏（仅保留最后两级）

---

### 3. PerformanceMonitor - 性能监控

**职责**: 为所有引擎提供统一的性能埋点

```swift
// 使用示例
let result = try await PerformanceMonitor.shared.track("operation.name") {
    try await someAsyncWork()
}

// 获取统计
let stats = await PerformanceMonitor.shared.aggregatedStats()
```

**特性**:
- 单调时钟 (mach_absolute_time)
- P95 延迟统计
- 环形缓冲区存储

---

### 4. ConcurrentScheduler - 并发调度

**职责**: 可控的并发任务调度

```swift
// 单任务
let result = try await ConcurrentScheduler.shared.schedule(priority: .high) {
    try await processFile(url)
}

// 批量处理
let results = try await ConcurrentScheduler.shared.mapConcurrently(items) { item in
    try await process(item)
}
```

**特性**:
- 并发限制 (maxConcurrency)
- 优先级队列
- 任务超时
- 背压控制 (maxQueueSize)

---

## 依赖关系

```
SwiftSweepUI → SwiftSweepCore
     ↓              ↓
MediaAnalyzerView → MediaAnalyzer → PerformanceMonitor
IOAnalyzerView    → IOAnalyzer    → ConcurrentScheduler
```

---

## 线程安全

所有核心组件使用 Swift `actor` 确保线程安全:

- `PerformanceMonitor` - actor
- `ConcurrentScheduler` - actor
- `MediaScanner` - actor
- `IOSelfTracer` - actor
- `IOAggregator` - actor

---

## 构建与测试

```bash
# 构建
swift build

# 测试
swift test

# 运行应用
open .build/debug/SwiftSweepApp.app
```

