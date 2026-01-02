# 项目设计文档：多语言包管理与Git仓库分析

**项目名称**：SwiftSweep - Polyglot Package Manager & Git Visualizer
**作者 / 时间**：JadeSnow7 / 2026-01-02
**项目类型**：开发者工具 / 效率工具
**适用平台**：macOS

---

## 1. 背景（Background）

在各平台开发过程中，Mac 开发者的机器上通常散布着多种包管理系统的产物：
1.  **包散落**：Homebrew (系统/CLI), npm (Node), pip (Python), gem (Ruby) 安装在不同路径。
2.  **孤儿包累积**：卸载主程序后，作为依赖被自动安装的库往往被遗忘占用空间。
3.  **Git 膨胀**：`.git` 目录因包含大量 dangling blobs 或从未清理的 merged branches 而占用数 GB 空间。
4.  **无统一视图**：开发者想“清理环境”时，需要在终端分别敲击多个 `autoremove` 或 `gc` 命令。

---

## 2. 目标与非目标（Goals & Non-Goals）

### Goals
-   **统一视图**：在一个列表中展示 Homebrew/npm/pip/gem 的所有全局安装包。
-   **孤儿检测**：识别并高亮显示无依赖关系的孤儿包（Orphaned Packages）。
-   **Git 清理**：一键执行 `git gc --prune=now`, `git remote prune origin`, `git clean`。
-   **安全执行**：所有操作必须经过 ProcessRunner 的安全封装，防止任意命令执行。

### Non-Goals
-   **不替代原生 CLI**：不做包升级、依赖解决等复杂功能，仅关注“发现”与“清理”。
-   **不支持 Windows/Linux**：深度依赖 macOS 文件路径结构。

---

## 3. 需求与约束（Requirements & Constraints）

### 功能需求
1.  **包扫描**：并行扫描 4 种包管理器，提取名称、版本、大小、依赖关系。
2.  **Git 扫描**：递归扫描指定目录下的所有 `.git` 文件夹，分析占用空间。
3.  **批量操作**：支持多选卸载。

### 非功能需求
-   **响应速度**：扫描需在 5s 内完成（使用并发）。
-   **鲁棒性**：若用户未安装某包管理器（如未安装 Node.js），不应导致扫描崩溃。

### 约束条件
-   **Sandbox**：App Sandbox 环境下，需用户授权访问 `/usr/local` 或 `~/.npm` 等目录，或通过 Helper 辅助。
-   **路径差异**：Apple Silicon (`/opt/homebrew`) vs Intel (`/usr/local`)。

---

## 4. 方案调研与对比（Alternatives Considered）🔥

### 包信息获取方案

| 方案 | 优点 | 缺点 | 结论 |
| :--- | :--- | :--- | :--- |
| **解析 Lock/Config 文件** | 极快，无需运行进程 | 格式复杂且经常变动；很难准确计算“安装大小”。 | ❌ |
| **调用 CLI (`brew list --json`)** | **最准确，官方支持；包含依赖关系。** | **需要 spawn 子进程，相对较慢。** | ✅ |

### Git 仓库发现方案

| 方案 | 优点 | 缺点 | 结论 |
| :--- | :--- | :--- | :--- |
| **全盘 `find`** | 简单 | 极慢，IO 密集。 | ❌ |
| **NSDirectoryEnumerator** | 原生 API | 仍需遍历大量文件。 | ❌ |
| **Project 目录白名单** | **极快；符合用户习惯。** | **需要用户指定代码根目录（如 `~/Projects`）。** | ✅ |

**最终选择**：并发调用各 CLI 工具获取列表；Git 扫描基于用户指定的 Project Root。

---

## 5. 整体架构设计（Design Overview）

### Provider 模式

```mermaid
flowchart TB
    subgraph UI
        PackageFinderView
    end

    subgraph Core
        PackageScanner[PackageScanner Actor]
        Protocol[PackageProvider Protocol]
    end

    subgraph Providers
        Homebrew[HomebrewProvider]
        Npm[NpmProvider]
        Pip[PipProvider]
    end

    UI --> PackageScanner
    PackageScanner --> Protocol
    Protocol <|-- Homebrew
    Protocol <|-- Npm
    Protocol <|-- Pip
```

所有 Provider 实现统一协议：
```swift
protocol PackageProvider {
    var type: PackageType { get }
    func isAvailable() async -> Bool
    func listPackages() async throws -> [PackageInfo]
    func uninstall(package: PackageInfo) async throws
}
```

---

## 6. 关键设计点（Key Design Decisions）

### 6.1 并发扫描 (TaskGroup)
*   **设计**：使用 `withTaskGroup` 并行启动所有 Provider 的扫描任务。
*   **原因**：`brew list` 和 `npm list` 可能各需 1-2 秒，串行会导致总耗时过长。并发可将总耗时压缩至最慢的那个任务。

### 6.2 环境变量注入
*   **问题**：App 启动时无法获得 Shell 的 PATH（如 `~/.nvm` 注入的 path）。
*   **解决**：维护一个常用路径白名单 (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.cargo/bin`)，在执行 ProcessRunner 时手动注入 PATH。

### 6.3 孤儿判断逻辑
*   **逻辑**：
    1. 获取所有包及其 `dependencies` 列表。
    2. 构建依赖有向图。
    3. 入度为 0 且标记为 `auto-installed` (如 brew leaves) 的包即为孤儿。

---

## 7. 并发与线程模型（Concurrency Model）

-   **Scanner Actor**：管理扫描状态，确保多次点击“刷新”不会导致进程爆炸。
-   **UI 渲染**：扫描结果包含成百上千个 Item，使用 `LazyVStack` 渲染，避免主线程卡顿。

---

## 8. 性能与资源管理（Performance & Resource Management）

### 性能瓶颈
-   **Git 仓库扫描**：如果 `node_modules` 层级太深，会导致文件遍历极慢。
    -   *优化*：扫描 `.git` 时跳过常见的忽略目录 (`node_modules`, `dist`, `build`)。

---

## 9. 风险与权衡（Risks & Trade-offs）

-   **误删风险**：用户可能不小心删除了系统依赖的 Python 包。
    -   *规避*：仅列出 User Site Packages，不触碰 System Python。对 Homebrew 核心包增加警告。

---

## 10. 验证与效果（Validation）

-   **集成测试**：在 CI 环境安装特定版本的 node 包，验证 Scanner 能否正确解析版本号和大小。
-   **UI 测试**：模拟 1000 个包的列表，滚动帧率需 > 55fps。

---

## 11. 可迁移性（macOS → iOS）

-   **不可迁移**：iOS 没有 shell，没有 brew/npm，此模块完全特定于 macOS 开发环境。

---

## 12. 后续规划（Future Work）

1.  **Galaxy 视图**：使用 SpriteKit 绘制包依赖关系的星系图（已在 Roadmap）。
2.  **漏洞扫描**：集成 `npm audit` / `pip audit` 检查 CVE 漏洞。

---

## 13. 总结（Takeaways）

Package Manager 模块通过将不同生态的 CLI 输出标准化为统一的数据模型，极大降低了开发者的维护心智负担。**Provider 模式** 的使用使得未来扩展 Rust (Cargo) 或 Go (Go Mod) 支持变得非常简单，仅需新增一个遵循协议的 Class。
