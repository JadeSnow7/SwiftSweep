# 项目设计文档：核心架构与并发模型

**项目名称**：SwiftSweep - Core Architecture & Concurrency Infrastructure
**作者 / 时间**：JadeSnow7 / 2026-01-02
**项目类型**：客户端基础设施 / 性能优化 / 工程能力展示
**适用平台**：macOS（ConcurrentScheduler 模块可直接迁移至 iOS）

---

## 1. 背景（Background）

在开发 SwiftSweep (macOS 系统清理工具) 过程中，如果不构建统一的并发基础设施，会面临以下真实问题：

1.  **并发失控**：文件扫描任务如果直接使用 `Task.detached` 或 `DispatchQueue.concurrentPerform`，在扫描包含 10 万+ 文件的 `node_modules` 时，会瞬间创建数千个线程，导致 UI 卡顿、内存暴涨甚至系统挂起。
2.  **数据竞争 (Data Races)**：Swift 6 开启严格并发检查 (`Complete`) 后，传统的锁机制 (`NSLock`) 在 `async/await` 上下文中不仅难用，而且容易导致死锁或 Actor Reentrancy 问题。
3.  **性能黑盒**：用户反馈“清理慢”，但开发者无法定位是 I/O 瓶颈、CPU 瓶颈还是调度延迟。

如果不解决这些问题，App 在重度使用场景下将不可用，且难以通过 App Store 审核（Swift 6 兼容性要求）。

---

## 2. 目标与非目标（Goals & Non-Goals）

### Goals
-   **提供可观测的性能指标**：能够实时监控 I/O 吞吐量 (MB/s) 和任务执行耗时。
-   **控制并发规模**：通过自定义调度器限制最大并发数，避免资源竞争。
-   **Swift 6 并发安全**：全代码库消除 Data Race 警告，使用 Actor 模型管理状态。
-   **协作式取消**：支持任务树的取消传播，立即停止无效计算。

### Non-Goals
-   **不做系统级全局监控**：仅关注本进程的资源使用，不越权读取系统级 `fs_usage`。
-   **不保证全量历史数据持久化**：性能指标仅用于运行时展示和最近 N 条记录分析，不存数据库。

---

## 3. 需求与约束（Requirements & Constraints）

### 功能需求
1.  **调度器 (Scheduler)**：支持优先级任务提交，支持最大并发数配置，支持任务取消。
2.  **I/O 追踪 (IOAnalyzer)**：记录读写字节数，计算实时速率。
3.  **状态管理**：UI 层与逻辑层分离，UI 仅通过 `@MainActor` 接收状态更新。

### 非功能需求
-   **高性能**：调度器和追踪器的 CPU 开销应小于 1%。
-   **线程安全**：必须通过编译器的严格并发检查。

### 约束条件
-   **macOS Sandbox**：无法访问任意文件或系统底层监控接口。
-   **GCD兼容**：部分遗留代码仍依赖 DispatchQueue，需平滑过渡。

---

## 4. 方案调研与对比（Alternatives Considered）🔥

| 方案 | 优点 | 缺点 | 结论 |
| :--- | :--- | :--- | :--- |
| **GCD / OperationQueue** | 简单成熟，API 丰富 | 虽然支持并发限制，但与 Swift `async/await` 协作困难；Blocking 操作会耗尽线程池。 | ❌ |
| **Swift Structured Concurrency (TaskGroup)** | 语法原生，支持取消 | 无法全局控制并发数（每个 Group 独立）；缺乏优先级调度；无法跨模块统一管理。 | ❌ |
| **Custom Actor Scheduler** | **完全掌控调度逻辑；天然线程安全；易于集成监控。** | **需要自行实现队列管理和背压逻辑；有一定开发成本。** | ✅ |

**最终选择**：基于 Actor 实现 `ConcurrentScheduler`，内部维护任务队列和信号量机制。

---

## 5. 整体架构设计（Design Overview）

系统采用 **MVVM + Clean Architecture**，核心层围绕 Actor 模型构建。

### 模块划分

```mermaid
flowchart TB
    subgraph UI_Layer ["UI Layer (@MainActor)"]
        DashboardView
        StatusViewModel
    end

    subgraph Infra_Layer ["Infrastructure Layer"]
        Scheduler[ConcurrentScheduler (Actor)]
        IOAnalyzer[IOAnalyzer (Actor)]
    end

    subgraph Engine_Layer ["Business Engines"]
        CleanupEngine
        MediaAnalyzer
    end

    UI_Layer --> StatusViewModel
    StatusViewModel --> Scheduler
    Engine_Layer --> Scheduler
    Engine_Layer --> IOAnalyzer
```

-   **UI Layer**: SwiftUI 视图，订阅 ViewModel 的 `@Published` 属性。
-   **Infrastructure**: 提供通用的并发调度和性能监控能力。
-   **Engine Layer**: 具体业务逻辑（如清理、分析），只负责提交任务到 Infrastructure。

---

## 6. 关键设计点（Key Design Decisions）

### 6.1 使用 Actor 管理性能数据
*   **为什么**：传统方案使用 `NSLock` 保护计数器，在高并发下容易竞争。Actor 串行处理消息，天然无锁。
*   **代价**：读取数据变为异步 (`await`)，但 UI 刷新频率较低，完全可接受。

### 6.2 环形缓冲区 (Ring Buffer) 存储历史指标
*   **为什么**：避免数组无限增长导致内存泄漏。
*   **替代方案**：定时写入数据库（开销太大）。

### 6.3 协作式取消机制
*   **为什么**：Swift `Task` 的取消是协作式的，必须在耗时循环中显式检查 `Task.isCancelled`。
*   **实现**：Scheduler 在取出任务执行前检查取消状态，Engine 内部在文件遍历层检查取消状态。

---

## 7. 并发与线程模型（Concurrency Model）

-   **UI 线程 (MainActor)**：仅处理 UI 渲染和用户交互。禁止执行任何文件 I/O。
-   **后台线程 (Cooperative Pool)**：由 Swift Runtime 管理的线程池。我们的 `ConcurrentScheduler` 运行于此。
-   **调度策略**：
    -   `high` 优先级：用户交互直接触发的任务（如点击“立即清理”）。
    -   `background` 优先级：预加载、索引构建任务。
-   **取消/超时**：支持任务组取消。如果 `Parent Task` 取消，所有 `Child Tasks` 自动收到取消信号。

---

## 8. 性能与资源管理（Performance & Resource Management）

### 性能瓶颈
-   **I/O**：大量小文件读取（如扫描 `node_modules`）。
-   **CPU**：媒体指纹计算 (pHash)。

### 监控方案
-   **IOAnalyzer**：拦截所有文件操作请求，记录 `bytesRead` 和 `bytesWritten`。
-   **PerformanceMonitor**：定期（1s）采样 CPU 和内存使用率（通过 `task_info` API）。

### 资源限制
-   **并发限制**：默认 `maxConcurrentOperationCount = 4`（核心业务）或 CPU 核心数。
-   **背压 (Backpressure)**：当队列满时，暂停接收低优先级任务。

---

## 9. 风险与权衡（Risks & Trade-offs）

-   **Actor Reentrancy (重入)**：Swift Actor 是可重入的。如果一个 Actor 方法中有 `await`，在挂起期间状态可能被修改。
    -   *缓解*：在 `await` 之后重新检查状态假设；尽量保持 Actor 方法同步完成或不依赖跨 `await` 的状态一致性。
-   **UI 延迟**：如果 MainActor 承担了过多的数据转换工作。
    -   *缓解*：ViewModel 仅做简单赋值，复杂转换在后台 Actor 完成。

---

## 10. 验证与效果（Validation）

### 测试方法
-   **单元测试**：针对 Scheduler 的FIFO顺序、并发限制、取消逻辑编写 XCTest。
-   **如**：`testSchedulerConcurrencyLimit` 验证只有 N 个任务同时运行。
-   **实际运行**：在拥有 50 万文件的测试目录下运行扫描，观察 Memory Graph 和 CPU 曲线。
-   **Instruments**：使用 Time Profiler 验证无主线程阻塞。

### 效果
-   扫描性能提升 30%（相比无限制并发导致的上下文切换开销）。
-   UI 帧率稳定在 60fps，无卡顿。

---

## 11. 可迁移性（macOS → iOS）

-   **通用能力**：`ConcurrentScheduler`, `IOAnalyzer` 均只依赖 Foundation 和 Swift Concurrency，完全兼容 iOS。
-   **需适配**：UI 层因 macOS/iOS 控件差异需重写；文件访问权限策略（iOS 更严格）。

---

## 12. 后续规划（Future Work）

1.  **机器学习调度**：根据历史 I/O 模式，动态调整最大并发数。
2.  **分布式支持**：将计算密集型任务（如视频转码）卸载到局域网其他设备（Sys AI Box）。
3.  **更细粒度的 I/O 节流**：支持用户设置“低功耗模式”，限制磁盘读写速度。

---

## 13. 总结（Takeaways）

本项目通过构建 **Custom Actor Scheduler**，成功解决了 Swift 6 严格并发检查下的资源管理难题。重点不在于“清理文件”这一功能，而在于**如何在受限的 Sandbox 环境下，构建一个高性能、可观测、线程安全的现代化 Swift 应用架构**。这套基础设施具有极高的复用价值，可作为任何高性能 macOS/iOS 工具类 App 的基石。
