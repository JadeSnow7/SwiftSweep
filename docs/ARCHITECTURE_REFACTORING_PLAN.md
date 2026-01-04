# Architecture Refactoring Plan / 架构重构计划

## Goal / 目标
Refactor SwiftSweep from MVVM to a Unidirectional Data Flow (UDF) architecture compliant with TS_008. / 将 SwiftSweep 从 MVVM 重构为符合 TS_008 的单向数据流（UDF）架构。

## Principles / 原则
- This is a multi-phase refactoring. Each phase is independently deployable. / 本计划分阶段进行，每阶段可独立部署。

## Architecture Overview / 架构总览
- View dispatches Actions. / View 派发 Action。  
- Reducer updates State (Pure Logic). / Reducer 更新 State（纯逻辑）。  
- Store publishes new State. / Store 发布新 State。  
- Effects handle Side Effects (Async/IO) and dispatch resulting Actions. / Effects 处理副作用（异步/IO）并派发结果 Action。  

```
Dispatch Action -> Reducer -> AppState -> Store Publish -> View Update
                         |
                         v
                     Effects (Async/IO) -> Dispatch Result Action
```

## Current Implementation Snapshot / 当前实现快照
- **State Layer**: `AppState` includes `NavigationState`, `UninstallState`, `CleanupState`, and `CleanupResult`. / `AppState` 已包含导航、卸载、清理及清理结果状态。  
  Files: `Sources/SwiftSweepCore/State/AppState.swift`
- **Action Layer**: `AppAction` now includes `NavigationAction`, `UninstallAction`, `CleanupAction` (with `setPendingSelection`, `scanFailed`, `confirmClean`, `cleanCompleted`, etc.). / `AppAction` 已包含导航/卸载/清理动作。  
  Files: `Sources/SwiftSweepCore/State/AppAction.swift`
- **Store + Reducer**: `AppStore` uses `appReducer`, and effects are injected via `setEffectHandler`. / `AppStore` 使用 `appReducer`，通过 `setEffectHandler` 注入 effects。  
  Files: `Sources/SwiftSweepCore/State/AppStore.swift`, `Sources/SwiftSweepCore/State/Reducer.swift`
- **Effects**: `uninstallEffects` and `cleanupEffects` are registered in `SwiftSweepApp`. / 在 `SwiftSweepApp` 中注册 `uninstallEffects` 与 `cleanupEffects`。  
  Files: `Sources/SwiftSweepCore/State/Effects/UninstallEffects.swift`, `Sources/SwiftSweepCore/State/Effects/CleanupEffects.swift`, `Sources/SwiftSweepUI/SwiftSweepApp.swift`
- **UI Migration**: `UninstallView` and `CleanView` now dispatch actions via `AppStore` (no `Task {}` in these views). / 卸载与清理视图已改为通过 Store 派发 Action。  
  Files: `Sources/SwiftSweepUI/UninstallView.swift`, `Sources/SwiftSweepUI/CleanView.swift`
- **Scheduler Usage**: Cleanup scan uses `ConcurrentScheduler`; Uninstall effects still use `Task.detached` for heavy work. / 清理扫描使用调度器，卸载 effects 仍使用 `Task.detached`。
- **Partial Coverage**: Other features still use local ViewModels/`Task {}`; full UDF coverage is not complete. / 其他功能仍保留 ViewModel 与 `Task {}`。

---

## Phase 1: Introduce AppState (State Layer) / 第一阶段：引入 AppState（状态层）
**Objective / 目标**: Create a Single Source of Truth. / 建立唯一事实来源。  
**Status / 状态**: Implemented (Navigation + Uninstall + Cleanup). / 已实现（导航 + 卸载 + 清理）。

[NEW] `Sources/SwiftSweepCore/State/AppState.swift`
```swift
public struct AppState: Equatable, Sendable {
    public var navigation: NavigationState
    public var uninstall: UninstallState
    public var cleanup: CleanupState
}

public struct NavigationState: Equatable, Sendable {
    public var pendingUninstallURL: URL?
}

public struct UninstallState: Equatable, Sendable {
    public enum Phase { case idle, scanning, scanned, deleting, done, error(String) }
    public var phase: Phase
    public var apps: [UninstallEngine.InstalledApp]
    public var selectedAppID: UUID?
    public var residuals: [UninstallEngine.ResidualFile]
    public var deletionPlan: DeletionPlan?
    public var deletionResult: DeletionResult?
    public var pendingSelectionURL: URL?
}

public struct CleanupState: Equatable, Sendable {
    public enum Phase { case idle, scanning, scanned, cleaning, completed, error(String) }
    public var phase: Phase
    public var items: [CleanupEngine.CleanupItem]
    public var cleanResult: CleanupResult?
    public var totalSize: Int64 { ... }
    public var selectedSize: Int64 { ... }
    public var selectedItems: [CleanupEngine.CleanupItem] { ... }
}
```

[NEW] `Sources/SwiftSweepCore/State/AppAction.swift`
```swift
public enum AppAction: Sendable {
    case navigation(NavigationAction)
    case uninstall(UninstallAction)
    case cleanup(CleanupAction)
}

public enum NavigationAction: Sendable {
    case requestUninstall(URL?)
    case clearUninstallRequest
}

public enum UninstallAction: Sendable {
    case startScan
    case scanCompleted([UninstallEngine.InstalledApp])
    case setPendingSelection(URL)
    case selectApp(UUID)
    case loadResidualsCompleted([UninstallEngine.ResidualFile])
    case prepareUninstall(UninstallEngine.InstalledApp)
    case planCreated(DeletionPlan)
    case cancelUninstall
    case confirmUninstall
    case startDelete
    case deleteCompleted(Result<DeletionResult, Error>)
    case reset
}

public enum CleanupAction: Sendable {
    case startScan
    case scanCompleted([CleanupEngine.CleanupItem])
    case scanFailed(String)
    case toggleItem(UUID)
    case selectAll
    case deselectAll
    case confirmClean
    case cancelClean
    case startClean
    case cleanCompleted(CleanupResult)
    case reset
}
```

---

## Phase 2: Create Store & Reducer / 第二阶段：创建 Store 与 Reducer
**Objective / 目标**: Centralize state mutations. / 集中状态变更逻辑。  
**Status / 状态**: Implemented. / 已实现。

[NEW] `Sources/SwiftSweepCore/State/AppStore.swift`
```swift
@MainActor
public final class AppStore: ObservableObject {
    public static let shared = AppStore()
    @Published public private(set) var state: AppState

    public typealias EffectHandler = (AppAction, AppStore) async -> Void
    private var effectHandler: EffectHandler?

    public func setEffectHandler(_ handler: @escaping EffectHandler) {
        effectHandler = handler
    }

    public func dispatch(_ action: AppAction) {
        state = appReducer(state, action)
        Task { await effectHandler?(action, self) }
    }
}
```

[NEW] `Sources/SwiftSweepCore/State/Reducer.swift`
```swift
public func appReducer(_ state: AppState, _ action: AppAction) -> AppState {
    var newState = state
    switch action {
    case .navigation(let a): newState.navigation = navigationReducer(state.navigation, a)
    case .uninstall(let a): newState.uninstall = uninstallReducer(state.uninstall, a)
    case .cleanup(let a): newState.cleanup = cleanupReducer(state.cleanup, a)
    }
    return newState
}
```

---

## Phase 3: Refactor UI to Pure Rendering / 第三阶段：UI 纯化
**Objective / 目标**: Remove Task {} from Views, subscribe to Store only. / 从 View 移除 Task {}，仅订阅 Store。  
**Status / 状态**: Partial (Uninstall + Cleanup complete). / 部分完成（卸载 + 清理已完成）。

[MODIFY] `Sources/SwiftSweepUI/UninstallView.swift`  
Before: `Button { Task { await viewModel.scanApps() } }`  
After: `Button { store.dispatch(.uninstall(.startScan)) }`

[MODIFY] `Sources/SwiftSweepUI/CleanView.swift`  
Before: `viewModel.startScan()`  
After: `store.dispatch(.cleanup(.startScan))`

[MODIFY] `Sources/SwiftSweepUI/SwiftSweepApp.swift`  
Inject `AppStore` as `@EnvironmentObject`. / 注入 `AppStore`。

---

## Phase 4: Centralize Effects / 第四阶段：副作用集中化
**Objective / 目标**: Move async work to Effect Handlers. / 将异步逻辑移至 Effect Handler。  
**Status / 状态**: Partial (Cleanup uses scheduler; Uninstall still uses Task.detached). / 部分完成（清理使用调度器，卸载仍使用 Task.detached）。

[NEW] `Sources/SwiftSweepCore/State/Effects/UninstallEffects.swift`
```swift
public func uninstallEffects(_ action: AppAction, _ store: AppStore) async {
    guard case .uninstall(let uninstallAction) = action else { return }
    switch uninstallAction {
    case .startScan:
        // Task.detached -> scan
        store.dispatch(.uninstall(.scanCompleted(apps)))
    // ...
    default: break
    }
}
```

[NEW] `Sources/SwiftSweepCore/State/Effects/CleanupEffects.swift`
```swift
public func cleanupEffects(_ action: AppAction, _ store: AppStore) async {
    guard case .cleanup(let cleanupAction) = action else { return }
    switch cleanupAction {
    case .startScan:
        // ConcurrentScheduler -> scan
        store.dispatch(.cleanup(.scanCompleted(items)))
    // ...
    default: break
    }
}
```

---

## Verification Plan / 验证计划

### Automated Tests / 自动化测试
- Unit test reducers with mock actions. / 使用模拟 action 单测 reducers。
- Integration test `AppStore.dispatch()` with mock effects. / 使用 mock effects 做 `AppStore.dispatch()` 集成测试。

### Manual Verification / 手动验证
- Verify UI reflects state changes correctly. / 验证 UI 正确反映状态变化。  
- Verify page transitions do not abort background tasks. / 验证页面切换不终止后台任务。  

---

## Risk Assessment / 风险评估
| Risk / 风险 | Mitigation / 缓解措施 |
| --- | --- |
| Large change scope / 变更范围大 | Phased rollout; each phase has isolated tests. / 分阶段发布，每阶段独立测试。 |
| Performance regression / 性能回退 | Profile before/after; use existing PerformanceMonitor. / 前后对比性能；复用 PerformanceMonitor。 |

---

## Phase 4.5: Architecture Hardening & Compliance / 架构强化与合规
**Objective / 目标**: Address architectural gaps and ensure strict adherence to TS_008 (Findings Remediation). / 解决架构缺陷，确保严格遵守 TS_008（缺陷修复）。

1. **Scheduler Integration / 调度器集成**  
   Finding: Scheduler layer isn’t consistently used; Uninstall effects still spawn Task.detached. / 发现：调度层未统一使用，卸载 effects 仍创建 Task.detached。  
   Plan:  
   - Use `ConcurrentScheduler.shared.schedule` in UninstallEffects. / 在卸载 effects 中使用调度器。  
   - Define cancellation/timeout mapping to actions. / 明确取消/超时对应 action。  

2. **App Identity & Stability / 应用标识与稳定性**  
   Finding: App identity may be regenerated on each scan. / 发现：应用标识可能随扫描重建。  
   Plan:  
   - Derive stable ID from bundleID + path (deterministic hash). / 基于 bundleID + path 生成稳定 ID。  

3. **State Integrity (Race Conditions) / 状态完整性（竞争条件）**  
   Finding: Residuals updates can race selection. / 发现：残留更新与选择存在竞态。  
   Plan:  
   - Verify `selectedAppID` before dispatching residual updates. / 派发残留更新前校验 selectedAppID。  

4. **Navigation Refactoring / 导航重构**  
   Status: Implemented (AppState + NavigationAction). / 状态：已实现（AppState + NavigationAction）。  

5. **Preselection & UX / 预选与体验**  
   Status: Implemented (pendingSelectionURL). / 状态：已实现（pendingSelectionURL）。  
   Remaining: Restore Apple App safety gating and error alerts in UninstallView. / 待补齐：Apple 应用卸载安全校验与错误提示。  

---

## Phase 5: Cleanup Feature Refactoring / 第五阶段：清理功能重构
**Objective / 目标**: Apply UDF to Cleanup Feature. / 将 UDF 架构应用于清理功能。  
**Status / 状态**: Partial (UI + Effects implemented; engine integration pending). / 部分完成（UI + Effects 已实现，执行引擎整合待完善）。

### Implemented / 已实现
- `CleanupState` includes `error(String)` + `cleanResult` and computed totals. / `CleanupState` 已包含错误与清理结果。  
- `CleanupAction` supports confirm/cancel/selectAll/deselectAll/scanFailed. / `CleanupAction` 已覆盖确认/取消/全选/失败等。  
- `CleanView` uses `AppStore` and confirmation sheet. / `CleanView` 已改为使用 Store。  
- `CleanupEffects` handles scan via scheduler and delete flow. / `CleanupEffects` 使用调度器扫描并执行清理。  

### Remaining / 待完成
- Move deletion logic into CleanupEngine (for reuse + auditing). / 将删除逻辑移回 CleanupEngine（便于复用与审计）。  

---

## Phase 6: Robustness & Testing / 第六阶段：健壮性与测试
**Objective / 目标**: Ensure stability and correctness of the new architecture. / 确保新架构的稳定性和正确性。

### Tasks / 任务
**Unit Tests / 单元测试**  
- Test uninstallReducer and cleanupReducer with various actions. / 用多种 action 测试 uninstallReducer 与 cleanupReducer。  
- Verify state transitions (e.g., scanning -> scanned, deleting -> done). / 验证状态迁移（如 scanning -> scanned，deleting -> done）。  

**Integration Tests / 集成测试**  
- Test AppStore flow with mocked effects (if possible) or end-to-end flows. / 使用 mock effect 或端到端流程测试 AppStore。  

**Performance Check / 性能检查**  
- Ensure main thread is not blocked during actions (using PerformanceMonitor). / 使用 PerformanceMonitor 确保主线程不被阻塞。  
