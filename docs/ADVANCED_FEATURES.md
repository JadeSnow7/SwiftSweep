# SwiftSweep 高级功能上手与面试亮点

目标：让新开发者 5-10 分钟跑通高级模块，同时给面试展示准备清晰的话术与演示脚本。

相关深度文档：
- `docs/MediaAnalyzer.md`
- `docs/IOAnalyzer.md`

---

## 1. 快速上手（5 分钟）

### 环境要求
- macOS 13+
- Xcode 15 / Swift 5.9

### 运行方式（推荐）
1. SwiftUI Preview 直接体验：
   - `Sources/SwiftSweepUI/MediaAnalyzerView.swift`
   - `Sources/SwiftSweepUI/IOAnalyzerView.swift`
2. 或者构建 App：
   - `swift build`
   - `swift run SwiftSweepApp`

### 最小代码示例

```swift
import SwiftSweepCore

// 1) 媒体分析（需要用户通过 fileImporter/NSOpenPanel 选择目录）
let root = URL(fileURLWithPath: "/Users/you/Movies")
let result = try await MediaAnalyzer.shared.analyze(
  root: root,
  onPhase: { print($0.rawValue) },
  onProgress: { current, total in print("\(current)/\(total)") }
)
print("Similar groups: \(result.similarGroups.count)")

// 2) I/O 分析（仅追踪 SwiftSweep 自身 I/O）
await IOAnalyzer.shared.startAnalysis(aggregationInterval: 1.0) { slice in
  print("Read: \(slice.readBytes) Write: \(slice.writeBytes)")
}
let temp = FileManager.default.temporaryDirectory.appendingPathComponent("io-demo.bin")
let data = Data(repeating: 0xAA, count: 8 * 1024 * 1024)
try await IOAnalyzer.shared.trackedWrite(data, to: temp)
_ = try await IOAnalyzer.shared.trackedRead(at: temp)
await IOAnalyzer.shared.stopAnalysis()
```

注意：沙盒下必须通过 fileImporter/NSOpenPanel 选择目录，才能获得安全作用域 URL。

---

## 2. Feature A：MediaAnalyzer（相似媒体检测）

### 数据流
```
MediaScanner -> MediaFile[]
             -> PerceptualHasher (pHash + SQLite 缓存)
             -> SimilarityDetector (LSH)
             -> SimilarGroup[]
```

### 关键实现
- 入口 Actor：`Sources/SwiftSweepCore/MediaAnalyzer/MediaAnalyzer.swift`
- pHash 计算（DCT 变换 + 多帧合并）：`Sources/SwiftSweepCore/MediaAnalyzer/PerceptualHasher.swift`
- LSH 加速相似检测：`Sources/SwiftSweepCore/MediaAnalyzer/SimilarityDetector.swift`
- 持久缓存：`Sources/SwiftSweepCore/MediaAnalyzer/pHashCache.swift`
  - SQLite 存储，使用 inode + mtime 失效

### 开发者上手要点
- `MediaScanner` 使用 `startAccessingSecurityScopedResource`，需要安全作用域 URL。
- `pHashCache` 自动在 `~/Library/Application Support/SwiftSweep/phash_cache.db` 写入。
- 默认 LSH 参数：bands=4, rows=16, threshold=10。

### 面试亮点话术
- “pHash 对缩放、压缩、轻微裁剪鲁棒，解决视觉相似难题。”
- “LSH 把 O(n^2) 的相似比较降为候选对集合，实际接近 O(n)。”
- “SQLite + inode/mtime 缓存让重复扫描成本极低。”

---

## 3. Feature B：IOAnalyzer（自身 I/O 性能分析）

### 数据流
```
trackedRead/Write/Contents
  -> IOSelfTracer
  -> IOEventBuffer (环形缓冲 + 采样)
  -> IOAggregator (时间片 + 路径统计)
  -> IOHotspotDetector (优化建议)
```

### 关键实现
- 入口 Actor：`Sources/SwiftSweepCore/IOAnalyzer/IOAnalyzer.swift`
- 自身 I/O 追踪：`Sources/SwiftSweepCore/IOAnalyzer/IOSelfTracer.swift`
- 环形缓冲与采样：`Sources/SwiftSweepCore/IOAnalyzer/IOEventBuffer.swift`
- 聚合与热点检测：`Sources/SwiftSweepCore/IOAnalyzer/IOAggregator.swift` `Sources/SwiftSweepCore/IOAnalyzer/IOHotspotDetector.swift`

### 开发者上手要点
- 不依赖 root/entitlement，仅追踪 SwiftSweep 自身 I/O。
- 路径自动脱敏（仅保留最后两级目录）。
- 采样率可动态调整，避免高频事件过载。

### 面试亮点话术
- “用环形缓冲 + 采样保证低开销可持续追踪。”
- “聚合为 1s 时间片，实时可视化吞吐/延迟。”
- “热点检测直接给出优化建议，强调可操作性。”

---

## 4. 面试演示脚本（3-5 分钟）

1. **媒体分析演示**
   - 打开 `MediaAnalyzerView` 预览，选择一个包含相似照片/视频的目录。
   - 展示相似分组与可回收空间。
   - 解释：pHash + LSH + SQLite 缓存。
2. **I/O 分析演示**
   - 打开 `IOAnalyzerView`，启动 tracing。
   - 在代码里执行 `trackedWrite`/`trackedRead`（或运行触发 I/O 的模块）。
   - 展示吞吐量曲线、热点路径与优化建议。
3. **收尾总结**
   - 强调“无特权、可解释、可扩展、可落地”。

---

## 5. 已实现扩展功能 ⭐ NEW

### 5.1 插件架构
- **CapCut 草稿解析插件**：已实现 MVP，支持解析草稿目录、检测孤儿素材。
- **插件管理**：`SweepPlugin` 协议 + `PluginManager`，支持开关与权限控制。
- 详见：`Sources/SwiftSweepCapCutPlugin/`

### 5.2 商业前端组件
| 组件 | 文件 | 功能 |
|------|------|------|
| 规则配置 | `InsightsAdvancedConfigView.swift` | 分组、优先级拖拽、灰度开关 |
| 虚拟表格 | `DataGridView.swift` | NSTableView 10k+ 行 |
| 数据看板 | `ResultDashboardView.swift` | Swift Charts 趋势图 |

### 5.3 AI Coding 能力
| 组件 | 文件 | 功能 |
|------|------|------|
| 智能解释器 | `SmartInterpreter.swift` | 证据 → 自然语言（白盒 AI）|
| 决策图 | `DecisionGraphView.swift` | 证据树可视化 |
| NL 解析器 | `NLCommandParser.swift` | 自然语言 → 过滤条件（中英双语）|

### 5.4 体验统一
- **UnifiedStorageView**：磁盘分析 + 媒体分析一体化入口
- **CleanupHistoryView**：清理前后对比、趋势追踪

---

## 6. 后续规划

- **系统级 I/O 追踪**：引入 `fs_usage`/`kdebug`（需额外权限）。
- **并发优化**：媒体哈希阶段接入 `ConcurrentScheduler`。
- **CapCut 增强**：草稿依赖图、影响分析、多版本对比。
