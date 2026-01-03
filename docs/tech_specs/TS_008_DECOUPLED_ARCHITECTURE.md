# TS_008: Decoupled Architecture Specification / 解耦架构规范

**Goal / 目标**: In the context of growing functional scale, ensure: / 在功能规模持续增长的背景下，确保：
- UI is never blocked. / UI 永不阻塞。
- State is predictable. / 状态可预测。
- Concurrency is strictly controlled. / 并发严格受控。
- Modules can evolve independently. / 模块可独立演进。

## 1. Top-Level Principles / 顶层原则

### P1. Unidirectional Dependency / 单向依赖
The system allows only the following dependency direction: / 系统只允许如下依赖方向：
```mermaid
graph TD
    UI[UI (Render)] --> State[State (State Machine)]
    State --> Scheduler[Scheduler (Task Orchestration)]
    Scheduler --> Execution[Execution (Domain / IO / Side Effects)]
```

**Prohibited Reverse Dependencies / 禁止的反向依赖：**
- ❌ **Execution** directly modifying UI. / **Execution** 直接修改 UI。
- ❌ **Scheduler** holding specific business logic. / **Scheduler** 持有具体业务逻辑。
- ❌ **State** actively fetching data or executing IO. / **State** 主动拉取数据或执行 IO。

### P2. Single Responsibility by Layer / 分层单一职责
| Layer / 层 | Allowed Responsibilities / 允许职责 | Explicitly Forbidden / 明确禁止 |
| :--- | :--- | :--- |
| **UI / Render** | Render based on state. / 基于状态渲染。 | Business logic, IO, Scheduling. / 业务逻辑、IO、调度。 |
| **State** | Describe state + State transitions. / 描述状态与状态迁移。 | IO, Thread management. / IO、线程管理。 |
| **Scheduler** | Task conflict detection, Concurrency control. / 任务冲突检测、并发控制。 | Modifying business state. / 修改业务状态。 |
| **Execution** | Execute specific logic. / 执行具体逻辑。 | Controlling UI, Deciding priority. / 控制 UI、决定优先级。 |

## 2. Four-Layer Architecture Definition / 四层架构定义

### 2.1 Render Layer (UI) / 渲染层（UI）
**Definition / 定义**: Pure functional rendering. `UI = f(State)` / 纯函数式渲染。
**Rules / 规则**:
1. UI can **only** subscribe to state. / UI 只能订阅状态。
2. UI **never** perceives threads / tasks / IO. / UI 不感知线程/任务/IO。
3. UI **does not** hold real business data copies. / UI 不持有真实业务数据副本。
   `View(state: AppState)`

**Compliance Checklist / 合规检查清单**:
- [ ] No `Task {}` or `DispatchQueue` in UI views. / UI 视图中不出现 `Task {}` 或 `DispatchQueue`。
- [ ] UI does not directly call scan/clean/network logic. / UI 不直接调用扫描/清理/网络逻辑。
- [ ] Page transitions do not cause task loss. / 页面切换不导致任务丢失。

### 2.2 State Layer (State Machine) / 状态层（状态机）
**Definition / 定义**: Single Source of Truth. / 唯一事实来源。
**Responsibilities / 职责**:
- Define all observable states. / 定义所有可观察状态。
- Receive `State Mutation`. / 接收 `State Mutation`。
- Strictly describe state transition rules. / 严格描述状态迁移规则。
  `Idle` → `Running` → `PartialResult` → `Completed` → `Cancelled`

**Key Rules / 关键规则**:
- State can only be committed, not "secretly modified". / 状态只能提交，不允许“偷偷修改”。
- State transitions must be **Predictable**, **Replayable**, **Debuggable**. / 状态迁移必须 **可预测、可回放、可调试**。

**Recommended Structure / 推荐结构**:
```swift
enum StateMutation {
  case taskStarted(TaskID)
  case progressUpdated(TaskID, Progress)
  case partialResult(TaskID, Snapshot)
  case taskFinished(TaskID, Result)
}
```

**Compliance Checklist / 合规检查清单**:
- [ ] No multiple "implicit state sources". / 不存在多个“隐式状态源”。
- [ ] Can replay UI via logs? / 是否可通过日志重放 UI？
- [ ] State updates are decoupled from threads? / 状态更新是否与线程解耦？

### 2.3 Scheduler Layer / 调度层
**Definition / 定义**: Manages "When to do what", not "What to do". / 负责“何时做什么”，而非“做什么”。
**Responsibilities / 职责**:
- Task lifecycle management. / 任务生命周期管理。
- Concurrency limit control. / 并发上限控制。
- Conflict detection. / 冲突检测。
- Cancellation and replacement strategies. / 取消与替换策略。
- Priority arbitration. / 优先级仲裁。

**Task Model / 任务模型**:
- `TaskDescriptor`: `id`, `type`, `priority`, `conflictKeys`, `cancellationPolicy`.

**Conflict Strategies / 冲突策略**:
- Page Re-scan: Discard new request. / 页面重扫：丢弃新请求。
- Switch Page: Retain background task. / 切页：保留后台任务。
- Repeat Uninstall: Kill old task. / 重复卸载：终止旧任务。

**Prohibitions / 禁止项**:
- ❌ Execute Disk IO. / ❌ 执行磁盘 IO。
- ❌ Change Business Data. / ❌ 修改业务数据。
- ❌ Perceive UI Lifecycle. / ❌ 感知 UI 生命周期。

**Compliance Checklist / 合规检查清单**:
- [ ] Can the scheduler implementation be replaced independently? / 调度器实现可独立替换？
- [ ] Are threads scattered across modules? / 线程是否分散在多个模块？
- [ ] Are all concurrency rules centralized? / 并发规则是否集中化？

### 2.4 Execution Layer (Domain Logic) / 执行层（领域逻辑）
**Definition / 定义**: The place that actually "does the work". / 实际“干活”的地方。
**Responsibilities / 职责**:
- File scanning, Uninstallation logic, Media analysis, Network requests. / 文件扫描、卸载逻辑、媒体分析、网络请求。
- Memory/Disk sync. / 内存/磁盘同步。

**Execution Model / 执行模型**:
- No UI dependency. / 不依赖 UI。
- No scheduling decisions. / 不做调度决策。
- Produces results, does not commit state. / 产出结果，不提交状态。
  `func execute(context) -> Result`

**Side Effects / 副作用**:
- Memory modification, Registration, Disk writing must be: / 内存修改、注册、磁盘写入必须：
    - After State change confirmation. / 在状态变更确认之后。
    - Executed by a dedicated synchronization module. / 由专门的同步模块执行。
    - ❗ Prohibition: "Writing to disk on the fly" during execution. / ❗ 禁止：执行过程中“随手写盘”。

## 3. Concurrency & Caching / 并发与缓存

### 3.1 Result Caching / 结果缓存
- UI always renders old results first, then progressively replaces. / UI 先渲染旧结果，再渐进替换。
- Switching pages ≠ Clearing tasks. / 切换页面 ≠ 清空任务。
- New task ≠ Clearing old state. / 新任务 ≠ 清空旧状态。

### 3.2 Conflict Writing Strategies / 冲突写入策略
- **Chunked Write**: Large scans. / **分块写入**：用于大规模扫描。
- **Priority Write-back**: Mutually exclusive resources. / **优先级回写**：资源互斥场景。
- **Functional Copy**: High conflict scenarios. (Copy-on-Write) / **函数式拷贝**：高冲突场景（写时拷贝）。

## 4. AI Development Norms / AI 开发规范
**Flow / 流程**: Plan → AI Draft → Human Review → AI Refine → Debug → Lock / 规划 → AI 初稿 → 人工审阅 → AI 精修 → 调试 → 锁定

**Rules / 规则**:
- ❌ AI cannot directly submit complex concurrency code. / ❌ AI 不可直接提交复杂并发代码。
- ❌ AI cannot generate cross-layer calls. / ❌ AI 不可生成跨层调用。
- ✅ AI used for: Templates, Pure functions, Docs, Tests. / ✅ AI 用于：模板、纯函数、文档、测试。

## 5. Self-Check (Verification) / 自检（验证）
- [ ] Can UI be mocked as a pure function? / UI 可否作为纯函数被 Mock？
- [ ] Does State completely describe the system? / 状态是否完整描述系统？
- [ ] Is Scheduler unaware of business logic? / 调度器是否不感知业务逻辑？
- [ ] Can Execution be parallelized/cancelled? / 执行是否可并行/可取消？
- [ ] Do tasks persist across page cuts? / 跨页面任务是否可持续？
- [ ] Are concurrency rules centralized? / 并发规则是否集中化？
- [ ] Is AI generated code controlled? / AI 生成代码是否受控？
