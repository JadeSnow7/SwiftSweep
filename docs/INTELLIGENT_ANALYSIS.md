# SwiftSweep 智能分析（Intelligent Analysis）功能设计与路线图

本文档定义 SwiftSweep 的“智能分析”能力边界、核心数据模型、架构落点与可执行的迭代路线图。目标是把 SwiftSweep 从“手动清单工具”升级为“可解释、可预览、可一键执行的系统助手”，同时保持 **安全第一、默认离线、最小权限**。

---

## 0. 当前实现（Status）

> 本文档最初是路线图；截至 `v1.2.1`，以下能力已落地（以 Developer ID 版本为主）。

### 已实现

- **Recommendation 数据模型**：`Sources/SwiftSweepCore/RecommendationEngine/Recommendation.swift`
- **规则引擎与开关**：`RecommendationEngine` 并行评估 + 超时保护；`RuleSettings` 支持启用/禁用规则
- **Smart Insights UI/CLI**：`Sources/SwiftSweepUI/InsightsView.swift` + `Sources/SwiftSweepCLI/SwiftSweep.swift`（`swiftsweep insights`）
- **统一执行链路**：`ActionExecutor`（去重/dry-run/结果统计）+ `ActionLogger`（审计日志）
- **已上线规则**：低磁盘空间、旧下载文件、开发者缓存、超大缓存、浏览器缓存、桌面旧截图/临时文件、废纸篓提醒、邮件附件、未使用应用（启发式）

### 待完善

- `installedApps` 与 `SwiftSweepAppInventory` 的深度集成（目前部分规则仍直接扫描 `/Applications`）
- 重 I/O 计算（目录体积/哈希/Vision 特征）的统一缓存与复用（`DirectorySizeCache` 目前为基础设施）
- 趋势洞察 / 媒体智能 / SweepAI（见 Roadmap 的 Phase 3+）

## 1. 目标（Goals）

- **从数据到决策**：将 `AnalyzerEngine` / `CleanupEngine` / `SystemMonitor` / `UninstallEngine` / `PackageScanner` / `SwiftSweepAppInventory` 的原始输出，转化为结构化建议（Recommendations/Insights）。
- **可解释**：每条建议都必须包含证据（Evidence）与影响说明（Impact），避免“黑盒”提示。
- **可控且安全**：默认 `dry-run`（预览），执行前必须二次确认；删除/卸载/特权操作统一走现有安全链路（allowlist + canonical path + helper）。
- **高性能**：优先利用系统元数据（Spotlight/文件属性）快速定位候选，再按需做递归/哈希等重任务；支持取消与渐进式结果。
- **隐私优先**：默认离线；如引入云端 LLM，仅上传脱敏的聚合统计并强制显式开关。

## 2. 非目标（Non-Goals）

- 不做“自动后台静默清理/删除”（无交互自动执行）。
- 不做“全盘内容索引/上传”。任何扫描范围必须清晰可见，且尊重沙盒/权限限制。
- 不以 LLM 替代规则与安全机制：LLM 只能做“解释/规划”，不能直接绕过白名单执行系统操作。

---

## 3. 设计原则（Design Principles）

1. **Safety by Default**
   - 默认 `dry-run`，默认只选中低风险项。
   - 所有 destructive action（删除/卸载/清理）必须走统一执行器，并提供回滚策略（能移入废纸篓则优先移入）。
2. **Explainable & Auditable**
   - 每条建议必须输出：触发规则、证据摘要、预计收益（空间/性能）、风险等级、可执行动作列表。
3. **Minimal Permissions**
   - 在 MAS（沙盒）下，只做“可用能力的最佳版本”；需要更高权限的功能在 UI 中明确标注（并解释原因）。
4. **Performance & Caching**
   - 重计算（目录递归大小、哈希、Vision 特征）必须可取消、后台执行、可缓存，避免重复工作。
5. **Stable API Contract**
   - Core 只产出结构化建议；UI/CLI 负责呈现与交互。避免把 UI 状态渗入 Core。

---

## 4. 核心数据模型（Core Contract）

当前已在 `Sources/SwiftSweepCore/RecommendationEngine/` 下实现以下核心概念（命名统一为 Recommendation）：

### 4.1 Recommendation（建议）

- `id`: 稳定字符串（用于去重、缓存、埋点）
- `title` / `summary`: 标题与一句话摘要
- `severity`: 严重程度（info / warning / critical）
- `risk`: 风险等级（low / medium / high）
- `confidence`: 置信度（low / medium / high）
- `estimatedReclaimBytes`: 预计可回收空间（可为空）
- `estimatedPerformanceImpact`: 预计性能收益（可为空）
- `evidence`: `[Evidence]`（必须非空）
- `actions`: `[Action]`（可为空：仅提示类 Insight）
- `requirements`: 权限/能力需求（例如：需要用户选择目录、需要 Helper、MAS 不支持等）

### 4.2 Evidence（证据）

用于解释“为什么这么建议”，推荐至少包含：

- `kind`: `path` / `metric` / `metadata` / `aggregate`
- `label`: 例如“Downloads 中 30 天未访问文件”
- `value`: 结构化数据（例如：文件数、总大小、阈值、来源 API）

### 4.3 Action（动作）

Action 是 Recommendation 的“可执行部分”，但执行必须通过统一执行器：

- `type`：`cleanupDelete` / `cleanupTrash` / `optimizeTask` / `openFinder` / `uninstallPlan` / `rescan`
- `payload`：例如路径列表、`OptimizationEngine.OptimizationTask.TaskType`、BundleID/URL 等
- `requiresConfirmation`：默认 true
- `supportsDryRun`：默认 true（能预览的尽量可预览）

> 执行层建议抽象为 `RecommendationExecutor`（UI/CLI 共享），内部复用 `CleanupEngine.performRobustCleanup` 与 `OptimizationEngine.run` 等现有实现，保证一致的权限与安全策略。
>
> 现状：已实现 `ActionExecutor` actor 作为统一执行器（清理类动作），并在 UI/Insights 中复用；卸载执行走 `DeletionPlan` 的专用安全链路。

---

## 5. 总体架构（Architecture）

### 5.1 数据来源（Signals）

Core 已具备主要信号源：

- 磁盘树与大文件：`AnalyzerEngine`（`buildTree` / `analyze`）
- 可清理项：`CleanupEngine`（扫描与安全删除链路）
- 系统指标：`SystemMonitor`（CPU/内存/磁盘/网络/电池）
- 应用与残留：`UninstallEngine`（InstalledApp + residualFiles）
- 包管理器：`PackageScanner`（brew/npm/pip/gem）
- 应用使用情况与智能过滤：`Packages/SwiftSweepAppInventory`（`SmartFilters`）

### 5.2 管线（Pipeline）

1. **Collect**：构建 `RecommendationContext`（轻量聚合；必要时异步补齐）
2. **Generate**：运行一组 `RecommendationRule`（纯函数/可测试）
3. **Rank**：按 `severity + reclaimBytes + risk + confidence` 排序，并做去重合并
4. **Present**：UI 展示建议卡片 + 证据详情 + 预览
5. **Execute**：统一执行器（dry-run → confirm → run → verify）

### 5.3 可扩展性（Rules as Plugins）

建议把每条规则实现为独立文件（例如 `Rules/OldDownloadsRule.swift`），便于迭代、测试与灰度开关：

- `RecommendationRule`：`func evaluate(context) async -> [Recommendation]`
- `RuleCapabilities`：声明需要的权限/输入（如“需要用户授予 Downloads 访问”）

---

## 6. 功能规格（Feature Specs）

本章节将原方案拆解为“可落地、低误报优先”的分层能力。

### 6.1 Smart Scan & Recommendations（启发式智能）

#### A. Unused Apps（长期未使用应用）

- **目标**：找出“长期未使用且体积较大”的应用，给出可解释建议。
- **当前实现（规则默认值）**：
  - 未使用阈值：`90` 天
  - 单应用最小体积：`50MB`
  - 总量阈值：`500MB` 才生成建议
  - lastUsedDate：基于文件元数据的启发式（可用性/准确性依赖系统行为）
- **后续方向**：与 `SwiftSweepAppInventory` 的 lastUsed/智能过滤打通，提升准确性与可配置性。
- **规则示例**：
  - `lastUsedDate < now - 90d`（可配置）
  - `appSize >= 50MB`（可配置）
  - `totalUnusedSize >= 500MB`（用于触发阈值）
  - `confidence`：若 lastUsedDate 为 nil，则不输出“未使用”，只输出“使用时间未知”（单独建议、低置信度）。
- **输出动作**：
  - 当前：`openFinder`（定位 /Applications）
  - 后续：`uninstallPlan`（DevID 可用；MAS 版本显示限制）

#### B. Old Downloads（下载目录陈旧文件）

- **目标**：识别 `~/Downloads` 中“过旧/低访问”的文件集合。
- **实现建议**：
  - 先用文件系统属性（`creationDate` / `contentAccessDate`）做基础规则。
  - 可选增强：Spotlight `kMDItemLastUsedDate`（不可用时降级）。
- **规则建议**：
  - `creationDate < now - 30d` 且（`lastAccessDate` 缺失或 `lastAccessDate < now - 30d`）
  - 对大文件单独加权（例如 > 200MB）
- **输出动作**：`cleanupTrash`（优先移入废纸篓）+ `openFinder`

#### C. Low Disk / Memory Pressure（健康告警）

- **目标**：当磁盘空间或内存压力达到阈值时给出可执行建议。
- **数据源**：`SystemMonitor.getMetrics()` +（可选）`AnalyzerEngine`（定位最大目录）
- **建议**：
  - 磁盘可用 < 10%：提示运行“智能清理 + Downloads/大文件定位”
  - 内存使用率 > 85%：提示关闭大内存应用、运行 `OptimizationEngine.clearMemory`（标注需要特权）

#### D. Developer Caches（高确定性开发缓存）

优先覆盖“确定性路径 + 可解释 + 误报低”的项目：

- Xcode：`~/Library/Developer/Xcode/DerivedData`、Simulators、Archives
- SwiftPM：`~/Library/Caches/org.swift.swiftpm`（视系统版本）
- 常见缓存：CocoaPods、Gradle、npm cache（仅提示，不默认删除）

> 跨全盘查找 `node_modules/.venv/target` 建议放到后续阶段，并要求用户选择扫描根目录（例如 `~/Projects`），避免全盘高成本与误报。

#### E. Ghost Caches（“幽灵”残留目录）

- **目标**：在 `~/Library` 的“已知残留根目录”下，找出疑似已卸载 App 的残留。
- **扫描范围**（MVP）：
  - `~/Library/Caches`
  - `~/Library/Application Support`
  - `~/Library/Preferences`
  - `~/Library/Containers`（注意误报；默认只做提示）
- **规则**：
  - 目录/文件名中包含 bundleID 形态（`com.vendor.app`）且 bundleID 不在已安装集合
  - 体积阈值（例如 > 50MB）才输出为可清理建议
- **动作**：默认 `openFinder` + `cleanupTrash`（风险 medium）

---

### 6.2 Storage Insights（趋势分析）

#### A. Snapshots（轻量快照）

- **目标**：提供“增长解释”和趋势图，而非保存全盘详情。
- **存储内容**（建议 JSON，带 schemaVersion）：
  - `timestamp`
  - `diskTotal/diskUsed/diskFree`
  - `buckets`: 少量类别桶（Downloads/DeveloperCaches/AppCaches/Photos/Other）体积估算（可为空）
- **采样策略**：
  - 默认前台采样：App 启动 + 每 6 小时（避免依赖后台必跑）
  - 后台采样作为增强：MAS 用 `BGAppRefreshTask`（不保证准时）；DevID 可用 LaunchAgent（不建议 LaunchDaemon）

#### B. Growth Explanation（增长解释）

当检测到 `usedBytes` 周增量超过阈值（例如 > 3GB）时：

- 给出 “增长了多少” + “最可能的来源桶变化”
- 提供一键跳转：打开 Analyze / Downloads 建议 / Developer Caches 建议

---

### 6.3 Media Intelligence（设备端 ML）

> 建议 **先限定为“用户选择的文件夹”**（例如 `~/Pictures/ToClean`），不要一开始就做 Photos.app 库级别集成。

#### A. Exact Duplicates（精确重复）

- **方法**：size 分桶 + hash（SHA256/xxHash）校验
- **输出**：重复组（保留一份、其余候选移入废纸篓）
- **风险**：low（但仍需确认）

#### B. Similar Photos（相似照片）

- **方法**：Vision `VNFeaturePrintObservation` + 距离阈值聚类
- **性能**：后台执行 + 缓存 feature print（key 用文件 path + mtime + size）
- **输出**：仅做“分组建议”，默认不自动选择删除（风险 medium）

#### C. Smart Tags（轻量分类，先做高确定性）

建议优先：

- Screenshots：路径/文件名/尺寸规则
- Documents：`VNRecognizeTextRequest` 文本密度阈值

“Memes”这类主观类别放后续或仅做实验功能。

---

### 6.4 SweepAI（可选：LLM 助手）

#### 定位

- **第一阶段**：本地规则化的自然语言命令（Command Palette），把输入映射到有限的 `ActionPlan`（clean/analyze/optimize/uninstall）。
- **第二阶段（可选）**：云端 Advisor（解释/规划），但执行仍由本地白名单动作驱动。

#### 安全与隐私要求（强制）

- 默认关闭；首次启用需明确告知数据范围与风险。
- 只上传脱敏聚合统计（大小/数量/类别/阈值），不上传原始文件名/路径/内容。
- LLM 输出必须走“工具调用/结构化计划”，并强制用户确认。

---

## 7. MAS vs Developer ID 能力矩阵（建议）

| 能力 | DevID（非沙盒） | MAS（沙盒） | 备注 |
|---|---|---|---|
| Smart Recommendations（基础） | ✅ | ✅（受目录访问限制） | 需要让用户选择目录/使用安全书签 |
| Uninstall（执行） | ✅（需 Helper） | ❌ | 现有 UI 已区分 |
| BG 采样 | ⚠️（LaunchAgent） | ⚠️（BGTask） | 都不保证准时；以前台采样为主 |
| 全盘扫描 | ✅（需权限） | ❌ | 建议用范围选择替代 |
| Vision 相似图片 | ✅ | ✅ | 但扫描范围应由用户授权 |

---

## 8. 分期路线图（Roadmap）

### Phase 0：基础设施（已完成 ✅）

- [x] `Recommendation`/`Evidence`/`Action` 数据模型（含排序语义）
- [x] `RecommendationEngine` + `RecommendationRule` + `RuleSettings`（并行评估 + 超时保护）
- [x] UI：Insights 页面 + 详情/确认弹窗
- [x] CLI：`swiftsweep insights [--json]`
- [x] 统一执行器：`ActionExecutor` + `ActionLogger`

**验收标准（已满足）**
- [x] 建议可查看证据与预计收益
- [x] destructive action 支持 dry-run + 二次确认（UI）

### Phase 1：低成本高价值（MVP）

- [x] Old Downloads（文件属性）
- [x] Low Disk Space（SystemMonitor）
- [x] Developer Caches / Large Caches / Browser Cache
- [x] Screenshot/Temp / Trash Reminder / Mail Attachments
- [x] Unused apps（启发式版本；AppInventory 深度集成待做）

### Phase 2：扩展扫描（控制误报）

- Ghost Caches（限定根目录 + 体积阈值）
- Developer junk（用户选定扫描范围内查找 node_modules/.venv/target）
- PackageScanner 结果与建议联动（例如提示清理 npm cache/unused packages，仅提示）

### Phase 3：趋势洞察

- Snapshots（JSON）+ 趋势图
- Growth Alerts（周增量解释 + 一键跳转）

### Phase 4：媒体智能

- Exact duplicates（hash）
- Similar groups（Vision + 缓存）
- Screenshots/Documents 标签（高确定性）

### Phase 5：SweepAI（可选）

- 本地 Command Palette → 结构化 ActionPlan
- 可选云端 Advisor（强制脱敏 + 工具调用 + 用户确认）

---

## 9. 测试与验证（Testing）

- **规则单测**：每条 `RecommendationRule` 使用合成的 `RecommendationContext` 输入，断言输出 recommendation 的 risk/confidence/bytes/证据完整性。
- **性能回归**：大目录扫描必须可取消；UI 不阻塞主线程；缓存命中可显著降低二次扫描耗时。
- **安全回归**：删除动作必须走 `CleanupEngine` 安全链路；所有路径标准化（canonicalPath）后再执行。

---

## 10. 开放问题（Open Questions）

- Snapshots 存储介质：JSON vs CoreData（建议先 JSON，schemaVersion 控制演进）
- “桶”划分策略：先用固定路径桶，还是引入按文件类型聚合（建议先固定路径桶）
- MAS 下目录授权的 UX：是否引入 Security-Scoped Bookmarks（建议引入，用于持久访问用户选定目录）
