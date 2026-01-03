# Decoupled Architecture Compliance Report / 解耦架构合规报告
**Date / 日期**: 2026-01-03
**Spec Version / 规范版本**: TS_008

## Executive Summary / 执行摘要
The codebase currently follows a **View-ViewModel-Engine** pattern (MVVM) rather than the strict **Unidirectional Data Flow (UDF)** defined in TS_008. While separation of concerns exists in the Core layer, the UI layer is heavily coupled with concurrency management and state mutations.  
当前代码库采用 **View-ViewModel-Engine**（MVVM）模式，而非 TS_008 定义的严格 **单向数据流（UDF）**。虽然 Core 层存在一定的职责分离，但 UI 层与并发管理、状态变更高度耦合。

## Compliance Metrics / 合规指标
| Layer / 层 | Status / 状态 | Critical Violations / 关键违规 |
| :--- | :--- | :--- |
| **Render (UI)** | 🔴 FAIL | UI Views/ViewModels directly spawn `Task {}` and `Task.detached`. / UI 视图/视图模型直接启动 `Task {}` 与 `Task.detached`。 |
| **State** | 🔴 FAIL | No Single Source of Truth. State is distributed across ViewModels, `@AppStorage`, and Singletons. / 缺乏单一事实来源，状态分散在 ViewModels、`@AppStorage` 与单例中。 |
| **Scheduler** | 🟢 PASS | `ConcurrentScheduler` exists and handles concurrency primitives correctly. implementation is decoupled. / `ConcurrentScheduler` 已存在并正确处理并发原语，实现解耦。 |
| **Execution** | 🟡 CAUTION | Engines are generally pure, but `UninstallViewModel` acts as an orchestrator mixing State/Scheduler responsibilities. / 引擎总体较纯，但 `UninstallViewModel` 承担调度/状态协调职责。 |

## Detailed Findings / 详细发现

### 1. Render Layer (UI) / 渲染层（UI）
**Violation / 违规**: UI perceives Tasks. / UI 感知任务。  
- **File / 文件**: `UninstallView.swift`
- **Evidence / 证据**: `Task { await viewModel.scanApps() }` in button actions. / 按钮中存在 `Task { await viewModel.scanApps() }`。
- **Rule Violation / 规则违反**: "UI never perceives threads / tasks / IO". / “UI 不感知线程/任务/IO”。
- **Impact / 影响**: UI logic is hard to test without mocking the async runtime; multiple clicks can spawn unmanaged races (though ViewModel tries to handle it). / 不模拟异步运行时就难以测试 UI；多次点击可能产生不可控竞争（尽管 ViewModel 尝试处理）。

### 2. State Layer / 状态层
**Violation / 违规**: Multiple Sources of Truth. / 多个事实来源。  
- **File / 文件**: `SwiftSweepApp.swift`, `UninstallView.swift`
- **Evidence / 证据**:
    - `NavigationState.shared` (Singleton) / `NavigationState.shared`（单例）
    - `@StateObject var viewModel` (Local View State) / `@StateObject var viewModel`（本地视图状态）
    - `@AppStorage` (UserDefaults) / `@AppStorage`（UserDefaults）
    - `UninstallCacheStore` (Separate Cache Store) / `UninstallCacheStore`（独立缓存存储）
- **Rule Violation / 规则违反**: "Strictly describe state transition rules... State only committed, not secretly modified". / “严格描述状态迁移规则……状态只能提交，不可偷偷修改”。
- **Impact / 影响**: Hard to "replay" the application state. Debugging requires inspecting multiple objects. / 难以“回放”应用状态，调试需检查多个对象。

### 3. Scheduler Layer / 调度层
**Status / 状态**: Good. / 良好。  
- **File / 文件**: `ConcurrentScheduler.swift`
- **Observation / 观察**: The `ConcurrentScheduler` actor correctly manages concurrency limits (`maxConcurrency`) and timeouts. It is unaware of business logic. / `ConcurrentScheduler` 正确管理并发上限与超时，且不感知业务逻辑。
- **Recommendation / 建议**: This module is a strong foundation. Use it to replace the ad-hoc `Task.detached` calls in ViewModels. / 该模块是良好基础，建议用于替换 ViewModel 中的临时 `Task.detached` 调用。

### 4. Execution Layer / 执行层
**Status / 状态**: Acceptable. / 可接受。  
- **File / 文件**: `CleanupEngine.swift`
- **Observation / 观察**: The engine takes inputs and produces `CleanupResultItem` outputs without directly modifying AppState. This fits the "Execution" definition. / 引擎输入输出清晰，产出 `CleanupResultItem`，不直接修改 AppState，符合“执行层”定义。
- **Issue / 问题**: It currently relies on `Task.isCancelled` which implies it knows about the Task environment, but this is standard Swift Concurrency. / 当前使用 `Task.isCancelled` 感知任务环境，但这属于 Swift 并发的常规用法。

## Recommendations / 建议
1. **Introduce AppState / 引入 AppState**: Create a global `AppState` struct holding `UninstallState`, `CleanupState`, etc. / 创建全局 `AppState` 结构体，包含 `UninstallState`、`CleanupState` 等。
2. **Refactor ViewModels / 重构 ViewModels**: Convert ViewModels into "Store" or "Feature" objects that receive **Actions** (Enum) instead of methods. / 将 ViewModel 转为“Store/Feature”，以 **Action**（枚举）驱动而非方法调用。
3. **Centralize Scheduling / 集中调度**: Move `Task.detached` logic out of ViewModels into a Middleware or explicit Scheduler/Effect handler that listens to State changes or Actions. / 将 `Task.detached` 从 ViewModel 移出，交由中间层或显式 Scheduler/Effect 处理。
