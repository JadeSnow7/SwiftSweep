# Decoupled Architecture Compliance Report / 解耦架构合规报告
**Date / 日期**: 2026-01-03
**Spec Version / 规范版本**: TS_008

## Executive Summary / 执行摘要
The UDF refactor has landed for **Uninstall** and **Cleanup**: UI now dispatches actions through `AppStore`, effects handle async work, and navigation state is centralized. However, the overall codebase remains mixed: several views still create `Task {}` directly, and non-migrated features keep local state (`@AppStorage`, view models). Scheduler usage is partial (Cleanup uses it; Uninstall still spawns `Task.detached`).  
UDF 已在 **卸载** 与 **清理** 功能落地：UI 通过 `AppStore` 派发 Action，effects 负责异步逻辑，导航状态也已集中。但整体仍是“混合架构”：部分页面仍直接创建 `Task {}`，未迁移模块保留本地状态（`@AppStorage`、ViewModel）。调度器使用仍不统一（清理已使用，卸载仍 `Task.detached`）。

## Compliance Metrics / 合规指标
| Layer / 层 | Status / 状态 | Critical Violations / 关键违规 |
| :--- | :--- | :--- |
| **Render (UI)** | 🟡 PARTIAL | Uninstall/Clean views are action-based; other views still spawn `Task {}`. / 卸载/清理已改为 Action 流；其它视图仍有 `Task {}`。 |
| **State** | 🟡 PARTIAL | AppState introduced, but `@AppStorage` and feature-local states still exist. / 已引入 AppState，但仍有 `@AppStorage` 与局部状态源。 |
| **Scheduler** | 🟡 PARTIAL | Cleanup uses `ConcurrentScheduler`; Uninstall effects still use `Task.detached`. / 清理已用调度器，卸载仍 `Task.detached`。 |
| **Execution** | 🟡 CAUTION | Engines are mostly pure; Cleanup deletion occurs directly in Effects. / 引擎总体纯，但清理删除逻辑在 Effects 内直接执行。 |

## Detailed Findings / 详细发现

### 1. Render Layer (UI) / 渲染层（UI）
**Progress / 进展**:  
- `UninstallView` and `CleanView` dispatch actions via `AppStore` (no direct `Task {}` in these views). / 卸载与清理视图已通过 Store 派发 Action。

**Violation / 违规**: UI still perceives Tasks in other views. / 其它视图仍直接感知 Task。  
- **File / 文件**: `Sources/SwiftSweepUI/InsightsView.swift`, `Sources/SwiftSweepUI/StatusView.swift`
- **Evidence / 证据**: Multiple `Task { ... }` blocks in button actions and onAppear flows. / 按钮与生命周期中仍存在 `Task { ... }`。
- **Impact / 影响**: UI concurrency is fragmented; hard to centralize cancellation and priority. / 并发分散，难以集中取消与优先级控制。

### 2. State Layer / 状态层
**Progress / 进展**:  
- `AppState` now includes `NavigationState`, `UninstallState`, and `CleanupState`. / AppState 已集中导航/卸载/清理状态。

**Violation / 违规**: Multiple sources of truth remain. / 仍存在多个事实来源。  
- **File / 文件**: `Sources/SwiftSweepUI/SettingsView.swift`
- **Evidence / 证据**: Extensive `@AppStorage` usage outside AppState. / 大量 `@AppStorage` 仍在 AppState 之外。
- **Impact / 影响**: State replay and global consistency are still limited. / 状态回放与一致性仍受限。

### 3. Scheduler Layer / 调度层
**Partial / 部分合规**:  
- **File / 文件**: `Sources/SwiftSweepCore/State/Effects/CleanupEffects.swift`
- **Observation / 观察**: Cleanup scan uses `ConcurrentScheduler` to throttle work. / 清理扫描已使用调度器限流。

**Gap / 缺口**:  
- **File / 文件**: `Sources/SwiftSweepCore/State/Effects/UninstallEffects.swift`
- **Observation / 观察**: Uninstall still uses `Task.detached` for scan/residuals. / 卸载仍使用 `Task.detached`。

### 4. Execution Layer / 执行层
**Status / 状态**: Acceptable with caution. / 可接受但需注意。  
- **File / 文件**: `Sources/SwiftSweepCore/UninstallEngine/UninstallEngine.swift`
- **Observation / 观察**: Uninstall engine remains pure and UI-agnostic. / 卸载引擎保持纯逻辑。

**Issue / 问题**: Cleanup deletion bypasses engine. / 清理删除绕过引擎。  
- **File / 文件**: `Sources/SwiftSweepCore/State/Effects/CleanupEffects.swift`
- **Impact / 影响**: Risks duplicating deletion logic and losing audit hooks. / 可能重复删除逻辑、丢失审计链路。

## Recommendations / 建议
1. **Complete UI Migration**: Move remaining views to action-driven store flows. / 继续迁移其它页面至 Store 驱动。
2. **Centralize Scheduling**: Route Uninstall effects through `ConcurrentScheduler`. / 卸载 effects 接入调度器。
3. **State Consolidation**: Wrap critical `@AppStorage` into AppState (or define explicit exemptions). / 将关键 `@AppStorage` 纳入 AppState，或明确豁免规则。
4. **Execution Consistency**: Move cleanup deletion into CleanupEngine for consistent auditing and reuse. / 将清理删除逻辑下沉至引擎，统一审计。
