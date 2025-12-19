# SwiftSweep 项目设计文档

## 1. 项目概述

SwiftSweep 是一个原生的 macOS 系统清理与优化工具，旨在提供现代化、高性能且用户友好的体验。它复刻并扩展了 Mole 的功能，完全使用 Swift 和 SwiftUI 构建，包含命令行界面 (CLI) 和图形用户界面 (GUI)。

> **核心目标**: 提供安全、高效的 macOS 系统维护方案，替代传统的 Shell 脚本工具。

---

## 2. 架构设计

采用模块化架构，核心逻辑与 UI 分离，确保 CLI 和 GUI 共享相同的业务逻辑。

```mermaid
graph TD
    subgraph "User Interface Layer"
        CLI[SwiftSweepCLI]
        GUI[SwiftSweepUI]
    end

    subgraph "Core Business Layer (SwiftSweepCore)"
        CE[CleanupEngine]
        RE[RecommendationEngine]
        AE[AnalyzerEngine]
        UE[UninstallEngine + DeletionPlan]
        OE[OptimizationEngine]
        PS[PackageScanner]
        GS[GitRepoScanner]
        SM[SystemMonitor]
        SH[Shared (Allowlist/Validation)]
    end

    subgraph "Integrations"
        INV[SwiftSweepAppInventory (Package)]
        EXT[External Tools: brew/npm/pip/gem/git]
    end

    subgraph "Privilege Layer"
        HLP[Privileged Helper (SMAppService + XPC)]
        AS[AppleScript Fallback]
    end

    CLI --> CE
    CLI --> AE
    CLI --> SM
    CLI --> RE

    GUI --> CE
    GUI --> AE
    GUI --> UE
    GUI --> OE
    GUI --> RE
    GUI --> INV
    GUI --> PS
    GUI --> GS

    CE --> SH
    UE --> SH
    OE --> HLP
    UE --> HLP

    OE --> AS

    PS --> EXT
    GS --> EXT
```

### 2.1 核心模块 (SwiftSweepCore)

| 模块 | 职责 | 备注 |
|------|------|------|
| **CleanupEngine** | 扫描可清理项并执行清理（默认移入废纸篓） | UI/CLI 均可用 |
| **RecommendationEngine** | Smart Insights：规则评估、证据/风险/置信度、动作生成 | 规则可开关，支持并行评估 |
| **ActionExecutor / ActionLogger** | 清理动作统一执行链路（去重、dry-run、结果统计、审计日志） | 供 Insights/Clean 复用 |
| **UninstallEngine + DeletionPlan** | 应用扫描、残留识别、删除计划预览与执行 | DevID 可执行；MAS 仅预览 |
| **AnalyzerEngine** | 构建磁盘树（Treemap/Tree/Top Files），支持隐藏文件开关与跳过目录 | 后台扫描 + 进度节流 |
| **OptimizationEngine** | 系统优化任务（DNS/Spotlight/内存/字体缓存/Dock/Finder） | 优先走 Helper，失败降级 AppleScript |
| **PackageScanner** | Homebrew/npm/pip/gem 扫描与包操作（卸载/升级等） | 依赖外部工具；仅 DevID UI 暴露 |
| **GitRepoScanner** | Git 仓库扫描、状态/体积、`gc`/`prune` 等维护操作 | 依赖 `git`，并发限流 |
| **SystemMonitor** | CPU/内存/磁盘/网络/电池采样与展示 | 注意线程安全 |
| **Shared** | Allowlist、路径规范化、错误码等共享安全组件 | Core/Helper 双侧校验 |

### 2.2 权限管理

SwiftSweep 的特权操作遵循“最小权限 + 可回滚”的策略：

1. **SMAppService + XPC Helper（推荐，macOS 13+）**
   - 使用 `ServiceManagement` 注册 LaunchDaemon，并通过 XPC 调用特权指令（DNS/Spotlight/purge/字体缓存、受控删除等）。
   - 优点：一次授权后可重复使用；命令与路径有 allowlist；输出可审计。
   - 缺点：需要签名/公证与更严格的打包流程；MAS 版本无法使用同等能力。

2. **AppleScript（降级路径）**
   - 当 Helper 未安装或不可用时，使用 `NSAppleScript` 执行 `do shell script ... with administrator privileges`。
   - 优点：实现简单，兼容性好。
   - 缺点：交互更频繁，且能力边界更窄（依赖用户授权与系统策略）。

> **构建差异**：MAS 版本启用 `-DSWIFTSWEEP_MAS`，部分功能（卸载执行、Packages/Git 等）会在 UI 隐藏或降级为只读。

---

## 3. 功能与能力

### 3.1 Smart Insights（Insights）

- **输出形态**：`Recommendation`（severity/risk/confidence/estimated reclaim）+ `Evidence`（可解释）+ `Action`（可执行）
- **规则评估**：`RecommendationEngine` 并行评估 + 超时保护，规则可在 `RuleSettings` 中开关
- **执行**：清理类动作统一走 `ActionExecutor`（去重、dry-run、结果统计、审计日志）
- **内置规则**（当前）：
  - 低磁盘空间（Critical/Warning）
  - 旧下载文件（Downloads）
  - 开发者缓存（Xcode/Gradle/等）
  - 超大缓存（用户缓存/系统缓存/浏览器缓存等）
  - 浏览器缓存（Safari/Chrome/Firefox/等）
  - 桌面旧截图/临时文件
  - 废纸篓提醒
  - 邮件附件（常见路径）
  - 未使用应用（基于文件元数据的启发式）

### 3.2 清理（Clean）

- **扫描范围**：系统/用户缓存、日志、浏览器数据等（按类别展示）
- **安全策略**：
  - 默认 **移入废纸篓**（可恢复）
  - 支持 **dry-run** 预览
  - UI 执行前 **二次确认**（展示列表与预计释放空间）

### 3.3 卸载（Uninstall）

- **应用发现**：扫描 `/Applications` 与 `~/Applications`
- **残留查找**：基于 Bundle ID / 应用名在 `~/Library` 常见目录中匹配（Caches/Preferences/Application Support/Containers 等）
- **删除计划**：`DeletionPlan`（包含路径解析、类型、体积、顺序）
- **执行策略**（DevID）：
  - 先尝试标准删除/移入废纸篓
  - 权限不足时再降级调用 Helper
  - 路径校验（allowlist + symlink escape 防护 + 系统只读路径阻断）
- **MAS**：受沙盒限制，只提供可用范围内的扫描/预览

### 3.4 分析（Analyze）

- **视图**：Treemap / Tree / Top Files
- **性能策略**：
  - 后台扫描，不阻塞 UI
  - 进度节流（避免 UI 频繁刷新）
  - 智能跳过常见大目录（如 `node_modules` / `.git` 等）
- **设置项**：可选择是否包含隐藏文件（`showHiddenFiles`）

### 3.5 优化（Optimize）

- **任务**：Flush DNS、Rebuild Spotlight、Clear Memory、Reset Dock/Finder、Clear Font Cache
- **特权处理**：优先走 Helper；不可用时降级 AppleScript（需要管理员授权）

### 3.6 Applications Inventory（Applications）

- **来源**：`Packages/SwiftSweepAppInventory`（独立 Package）
- **能力**：应用分类/筛选、体积扫描（浅/深）、跳转卸载等

### 3.7 Packages & Git Repos（仅 DevID UI）

- **Package Finder**：Homebrew（Formula/Cask）、npm、pip、gem 扫描；支持包 **卸载/升级**（带确认 + 可复制命令）
- **Git Repos**：扫描常见开发目录，展示 clean/dirty 与 `.git` 体积；支持 `git gc` / `git remote prune`

> 注：对外部工具的操作均需要显式确认，并优先提供“复制命令”以便用户自行执行与审计。

---

## 4. UI/UX 设计 (SwiftUI)

### 4.1 导航结构
采用两栏式布局 (`NavigationSplitView`)，左侧侧边栏导航，右侧内容区。

| 视图 | 功能描述 |
|------|----------|
| **StatusView** | 仪表盘展示系统健康度、实时资源监控（CPU/内存/磁盘/网络/电池）。 |
| **InsightsView** | Smart Insights 列表与详情（证据/风险/置信度/预计收益），支持一键清理（需确认）。 |
| **CleanView** | 清理扫描结果列表，按类别分组，支持二次确认与结果统计。 |
| **UninstallView** | 应用列表 + 残留文件，删除计划预览与执行（MAS 仅预览）。 |
| **OptimizeView** | 优化任务卡片与“Run All”，特权任务通过 Helper/AppleScript 运行。 |
| **AnalyzeView** | 路径选择器，扫描进度，大文件/目录树与 Treemap（支持隐藏文件开关）。 |
| **MainApplicationsView** | 应用清单：分类/筛选/深度扫描体积，并可一键跳转卸载。 |
| **PackageFinderView** | Packages & Git Repos：包扫描与操作（卸载/升级）、Git 仓库维护（仅 DevID 版本）。 |
| **SettingsView** | 偏好设置、Helper 安装状态管理、关于页面。 |

### 4.2 交互细节
- **暗色模式支持**: 全面适配 macOS Dark Mode。
- **动画**: 扫描进度条、环形图动态加载。
- **反馈**: 操作成功/失败的 Toast 或 Alert 提示。

---

## 5. 项目结构与文件

```
SwiftSweep/
├── Package.swift               # SPM 配置
├── Sources/
│   ├── SwiftSweepCore/         # 核心逻辑
│   │   ├── CleanupEngine/
│   │   ├── UninstallEngine/
│   │   ├── SystemMonitor/
│   │   ├── AnalyzerEngine/
│   │   ├── OptimizationEngine/
│   │   ├── RecommendationEngine/
│   │   ├── PackageScanner/
│   │   ├── GitRepoScanner/
│   │   ├── Shared/
│   │   └── PrivilegedHelper/   # Helper 客户端代码
│   ├── SwiftSweepCLI/          # 命令行入口（ArgumentParser）
│   └── SwiftSweepUI/           # SwiftUI 界面（Views + Resources）
├── Packages/                   # 内置子包（例如 SwiftSweepAppInventory）
├── Helper/                     # Privileged Helper（XPC daemon）
│   ├── main.swift
│   ├── Info.plist
│   └── com.swiftsweep.helper.plist
├── scripts/                    # 打包/签名脚本（Universal build 等）
├── SwiftSweepMAS/              # MAS（沙盒）版本工程
├── .github/workflows/          # CI（Notarize + Release）
└── Tests/                      # 单元测试
```

---

## 6. 开发路线图 (Roadmap)

### Phase 1: 基础架构 (已完成 ✅)
- [x] SPM 项目结构搭建
- [x] 核心引擎移植 (Cleanup, SystemMonitor)
- [x] CLI 基础命令实现

### Phase 2: UI 实现 (已完成 ✅)
- [x] SwiftUI 界面框架
- [x] 各功能模块 UI 实现
- [x] `AnalyzeView` 性能优化 (后台扫描)

### Phase 3: 权限系统（持续完善）
- [x] AppleScript 临时提权（降级路径）
- [x] SMAppService + XPC Helper（基础能力：优化任务 + 卸载删除兜底）
- [ ] Helper 能力矩阵完善与版本管理（协议/向后兼容）

### Phase 4: 发布与交付
- [x] Uninstall 删除计划与执行（DevID）
- [x] Universal 打包脚本（签名 + DMG）
- [ ] CI 公证（GitHub Actions notarytool）与 Release 流程完善
- [ ] 单元测试覆盖与回归策略

> 智能分析的扩展路线（趋势/媒体智能/LLM Advisor）请见 `docs/INTELLIGENT_ANALYSIS.md`。
