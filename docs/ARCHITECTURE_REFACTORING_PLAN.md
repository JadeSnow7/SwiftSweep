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

---

## Phase 1: Introduce AppState (State Layer) / 第一阶段：引入 AppState（状态层）
**Objective / 目标**: Create a Single Source of Truth. / 建立唯一事实来源。

[NEW] `Sources/SwiftSweepCore/State/AppState.swift`
```swift
// Global application state
public struct AppState: Equatable {
    public var navigation: NavigationState
    public var uninstall: UninstallState
    public var cleanup: CleanupState
    // ... other feature states
}

public struct UninstallState: Equatable {
    public enum Phase { case idle, scanning, scanned, deleting, done, error(String) }
    public var phase: Phase = .idle
    public var apps: [InstalledApp] = []
    public var selectedAppID: UUID?
    public var residuals: [ResidualFile] = []
}
```

[NEW] `Sources/SwiftSweepCore/State/StateMutation.swift`
```swift
public enum AppAction {
    case uninstall(UninstallAction)
    case cleanup(CleanupAction)
    // ...
}

public enum UninstallAction {
    case startScan
    case scanCompleted([InstalledApp])
    case selectApp(UUID)
    case loadResidualsCompleted([ResidualFile])
    case startDelete
    case deleteCompleted(Result<Void, Error>)
}
```

---

## Phase 2: Create Store & Reducer / 第二阶段：创建 Store 与 Reducer
**Objective / 目标**: Centralize state mutations. / 集中状态变更逻辑。

[NEW] `Sources/SwiftSweepCore/State/AppStore.swift`
```swift
@MainActor
public final class AppStore: ObservableObject {
    @Published public private(set) var state: AppState
    private let scheduler: ConcurrentScheduler
    
    public init(initial: AppState = .init(), scheduler: ConcurrentScheduler = .shared) {
        self.state = initial
        self.scheduler = scheduler
    }
    
    public func dispatch(_ action: AppAction) {
        // 1. Reduce
        state = reduce(state, action)
        // 2. Side effects (async) handled by Middleware
        Task { await runEffects(action) }
    }
}
```

[NEW] `Sources/SwiftSweepCore/State/Reducer.swift`
```swift
func reduce(_ state: AppState, _ action: AppAction) -> AppState {
    var newState = state
    switch action {
    case .uninstall(let a):
        newState.uninstall = uninstallReducer(state.uninstall, a)
    // ...
    }
    return newState
}
```

---

## Phase 3: Refactor UI to Pure Rendering / 第三阶段：UI 纯化
**Objective / 目标**: Remove Task {} from Views, subscribe to Store only. / 从 View 移除 Task {}，仅订阅 Store。

[MODIFY] `Sources/SwiftSweepUI/UninstallView.swift`  
Before: `Button { Task { await viewModel.scanApps() } }`  
After: `Button { store.dispatch(.uninstall(.startScan)) }`

[MODIFY] `Sources/SwiftSweepUI/SwiftSweepApp.swift`  
Inject AppStore as `@EnvironmentObject`. / 注入 AppStore 作为 `@EnvironmentObject`。

---

## Phase 4: Centralize Effects / 第四阶段：副作用集中化
**Objective / 目标**: Move async work to Effect Handlers. / 将异步逻辑移至 Effect Handler。

[NEW] `Sources/SwiftSweepCore/State/Effects/UninstallEffects.swift`
```swift
func runUninstallEffects(_ action: UninstallAction, store: AppStore) async {
    switch action {
    case .startScan:
        let apps = try await UninstallEngine.shared.scanInstalledApps()
        await MainActor.run { store.dispatch(.uninstall(.scanCompleted(apps))) }
    // ...
    }
}
```

---

## Verification Plan / 验证计划

### Automated Tests / 自动化测试
- Unit test `reduce()` with mock actions. / 使用模拟 action 单测 `reduce()`。
- Integration test `AppStore.dispatch()` with mock Scheduler. / 使用 mock Scheduler 做 `AppStore.dispatch()` 集成测试。

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
   Finding: Scheduler layer isn’t actually used; effects still spawn Task.detached directly. / 发现：调度层未被实际使用，effects 仍直接创建 Task.detached。  
   Plan:  
   - Update UninstallEffects to use `ConcurrentScheduler.shared.schedule` instead of `Task.detached`. / 用 `ConcurrentScheduler.shared.schedule` 替换 `Task.detached`。  
   - Update AppStore to properly utilize the scheduler for effect coordination if needed. / 必要时让 AppStore 使用调度器协调 effects。  

2. **App Identity & Stability / 应用标识与稳定性**  
   Finding: App identity (UUID) is regenerated on every scan, breaking selection stability. / 发现：应用 ID 每次扫描重建，导致选择不稳定。  
   Plan:  
   - Modify `InstalledApp` to derive id from bundleID + path hash. / 基于 bundleID + path hash 生成稳定 id。  
   - Ensure `UninstallEngine` returns stable IDs. / 确保 `UninstallEngine` 返回稳定 id。  

3. **State Integrity (Race Conditions) / 状态完整性（竞争条件）**  
   Finding: Residuals updates can race selection. / 发现：残留结果更新与选择存在竞态。  
   Plan:  
   - In UninstallEffects, check `store.state.uninstall.selectedAppID` matches the request before dispatching `loadResidualsCompleted`. / 在派发 `loadResidualsCompleted` 前校验 selectedAppID。  

4. **Navigation Refactoring / 导航重构**  
   Finding: NavigationState is a singleton outside AppState. / 发现：导航状态是 AppState 之外的单例。  
   Plan:  
   - Move NavigationState properties into AppState (e.g., `AppState.navigation`). / 将导航状态并入 AppState。  
   - Eliminate `NavigationState.shared` singleton. / 移除 `NavigationState.shared` 单例。  
   - Update MainApplicationsView and SwiftSweepApp to use `store.dispatch(.navigation(.requestUninstall(...)))`. / 更新为通过 store 派发导航 action。  

5. **Preselection & UX / 预选与体验**  
   Finding: Preselection fails if scan isn't done; Safety toggles missing. / 发现：未扫描完成时预选失败；安全开关缺失。  
   Plan:  
   - Implement “Pending Selection” state in UninstallState. / 在 UninstallState 中加入“待选中”状态。  
   - Restore PathValidator checks for Apple Apps settings. / 恢复 Apple 应用卸载设置的校验。  
   - Ensure phase = .error displays alerts in UninstallView. / 确保 `.error` 在 UI 中弹出提示。  

---

## Phase 5: Cleanup Feature Refactoring / 第五阶段：清理功能重构
**Objective / 目标**: Apply UDF to Cleanup Feature. / 将 UDF 架构应用于清理功能。

### Work Breakdown / 工作拆解
**State & Actions / 状态与行为**  
- Enhance CleanupState (already in AppState) if needed. / 视需要增强 CleanupState。  
- Verify CleanupAction covers all use cases (scan, toggle, clean). / 校验 CleanupAction 覆盖扫描、勾选、清理等场景。  

**Effects / 副作用**  
- Create `Sources/SwiftSweepCore/State/Effects/CleanupEffects.swift`. / 新增 CleanupEffects。  
- Implement effects for startScan (calling CleanupEngine). / 实现 startScan 的 effect（调用 CleanupEngine）。  
- Implement effects for startClean (executing deletion). / 实现 startClean 的 effect（执行清理）。  

**UI Refactoring / UI 重构**  
- Refactor `CleanView.swift` to use AppStore. / 将 `CleanView.swift` 改为使用 AppStore。  
- Replace CleanViewModel (if exists) or direct Engine calls. / 替换 CleanViewModel（如存在）或直接引擎调用。  

**Reducer / Reducer**  
- Ensure cleanupReducer correctly handles all actions and updates state. / 确保 cleanupReducer 正确处理 action 并更新状态。  

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
