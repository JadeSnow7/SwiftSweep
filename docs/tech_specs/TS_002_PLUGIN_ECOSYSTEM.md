# 项目设计文档：插件生态与 Sys AI Box 集成

**项目名称**：SwiftSweep - Plugin Ecosystem & Sys AI Box Integration
**作者 / 时间**：JadeSnow7 / 2026-01-02
**项目类型**：可扩展架构 / 软硬协同 / 工程能力展示
**适用平台**：macOS

---

## 1. 背景（Background）

在 SwiftSweep 的初期版本中，所有的清理逻辑（如 cache, log, trash）都硬编码在 App 内部。这带来了以下问题：
1.  **扩展性差**：每支持一个新的应用清理（如 CapCut, Xcode, Docker），都需要发版更新 App。
2.  **安全性风险**：如果允许插件包含可执行代码，难以通过 Apple 的 Hardened Runtime 审核，且容易引入恶意软件。
3.  **计算瓶颈**：本地计算复杂的 AI 任务（如视频分析）会显著占用用户 CPU/GPU，影响前台体验。

我们希望构建一个既能灵活扩展清理规则，又能利用外部算力的插件生态。

---

## 2. 目标与非目标（Goals & Non-Goals）

### Goals
-   **零代码插件**：插件仅包含 Data Pack (JSON 规则和资源)，不包含可执行代码，确保绝对安全。
-   **热更新**：支持从远程 Store 动态下载和分发插件，无需 App 发版。
-   **算力卸载**：支持将重度任务卸载到局域网内的 Sys AI Box 设备运行。
-   **无缝配对**：实现类 Apple TV 的简单设备配对流程 (Device Flow)。

### Non-Goals
-   **不支持动态库加载**：不加载 `.dylib` 或 `.bundle`，严格遵守 Sandbox 限制。
-   **不提供公共插件市场后端**：Plugin Store 仅读取 GitHub 托管的静态 JSON，不开发复杂的 SaaS 后端。

---

## 3. 需求与约束（Requirements & Constraints）

### 功能需求
1.  **插件管理**：浏览、安装、卸载、校验 (SHA256)。
2.  **规则引擎**：解析插件中的 JSON 规则并执行文件扫描。
3.  **设备协同**：发现 Sys AI Box，鉴权，提交任务，获取结果。

### 非功能需求
-   **安全性**：必须校验插件完整性；必须通过 HTTPS（生产环境）通信。
-   **兼容性**：插件格式需向前兼容。

### 约束条件
-   **Apple Hardened Runtime**：禁止 JIT 和无签名代码执行。
-   **App Transport Security (ATS)**：默认禁止 HTTP，需针对局域网 IP 做特殊配置。

---

## 4. 方案调研与对比（Alternatives Considered）🔥

### 插件机制对比

| 方案 | 优点 | 缺点 | 结论 |
| :--- | :--- | :--- | :--- |
| **Swift Bundle (.bundle)** | 原生支持，可包含代码 | 无法在 Hardened Runtime 下动态加载（需由主 App 签名）；安全风险高。 | ❌ |
| **Lua/JS 脚本引擎** | 灵活，逻辑描述能力强 | 引入解释器增加了包体积；审核风险；性能一般。 | ❌ |
| **Data Pack (JSON)** | **绝对安全（无代码执行）；易于编写；跨平台。** | **逻辑表达能力有限（仅能做模式匹配），无法处理复杂逻辑。** | ✅ |

### 协同通信对比

| 方案 | 优点 | 缺点 | 结论 |
| :--- | :--- | :--- | :--- |
| **Bonjour/Zeroconf** | 自动发现，体验好 | 仅限本地网络；实现较繁琐。 | ❌ |
| **手动 IP + Device Flow** | **简单可靠；适用于任何网络环境；OAuth 2.0 标准安全。** | **用户需手动输入一次 URL。** | ✅ |

**最终选择**：采用 **Data Pack** 插件架构 + **OAuth 2.0 Device Flow** 进行外部设备协同。

---

## 5. 整体架构设计（Design Overview）

### 插件与协同架构

```mermaid
flowchart LR
    subgraph SwiftSweep App
        PluginStore[PluginStore View]
        PluginMgr[PluginStoreManager]
        RuleEngine[Rule Engine]
        Network[Networking]
    end

    subgraph External
        GitHub[GitHub (Plugins.json + Zips)]
        AIBox[Sys AI Box (Ubuntu/Docker)]
    end

    PluginStore --> PluginMgr
    PluginMgr -- Fetch Catalog --> GitHub
    PluginMgr -- Download Zip --> GitHub
    PluginMgr --> RuleEngine
    
    RuleEngine -- Task Request --> Network
    Network -- HTTP/JSON --> AIBox
```

-   **PluginStoreManager**: 负责从 GitHub 获取元数据，下载并校验 ZIP 包，解压到 `AppSupport/Plugins` 目录。
-   **SysAIBoxIntegration**: 负责设备握手、Token 管理和任务分发。

---

## 6. 关键设计点（Key Design Decisions）

### 6.1 Data Pack Only (无代码插件)
*   **为什么**：这是通过 Mac App Store 审核的唯一可行路径。所有“执行逻辑”必须预埋在主 App 中，插件只能提供“配置”。
*   **代价**：丧失了极低成本支持全新功能的能力（例如支持全新的数据库格式清理），必须等待主 App 更新引擎。

### 6.2 设备配对流程 (OAuth 2.0 Device Grant)
*   **为什么**：避免用户在 Sys AI Box 输入复杂的账号密码；避免在 App 端明文存储凭证。
*   **流程**：
    1. App 请求 `POST /device/code`。
    2. Box 返回 `user_code` (如 `ABCD-1234`) 和验证 URL。
    3. 用户在浏览器打开验证 URL 输入代码。
    4. App 轮询 `POST /device/token` 直到获得 Access Token。

### 6.3 本地 HTTP 允许 (ATS Exception)
*   **设计**：在生产环境强制 HTTPS，但在开发环境 (`DEBUG`) 和私有 IP 段允许 HTTP。
*   **原因**：Sys AI Box 通常部署在该用户的内网服务器，配置有效 SSL 证书非常困难。

---

## 7. 并发与线程模型（Concurrency Model）

-   **插件下载**：使用 `NSURLSession` 的 `async/await` API，不阻塞主线程。
-   **规则执行**：插件规则被加载到内存后，由 `ConcurrentScheduler`（见 TS_001）调度执行。插件规则执行等同于普通的清理任务。

---

## 8. 性能与资源管理（Performance & Resource Management）

-   **懒加载**：App 启动时不加载所有插件规则，仅在用户进入“扫描”页面时异步加载。
-   **缓存**：`plugins.json` 目录和已下载的插件包在本地缓存，支持 ETag/Last-Modified 检查避免重复下载。

---

## 9. 风险与权衡（Risks & Trade-offs）

-   **GitHub 访问性**：国内用户可能无法访问 GitHub Raw 内容。
    -   *缓解*：未来可支持配置自定义 CDN 镜像源。
-   **插件规则冲突**：不同插件可能定义了相同的清理路径。
    -   *设计*：引擎层检测路径重叠，自动去重，避免重复计算或冲突。

---

## 10. 验证与效果（Validation）

### 测试方法
-   **Mock Server**：使用 Python Flask 搭建 Mock Sys AI Box，验证配对流程和 Token 刷新逻辑。
-   **Checksum 校验**：篡改下载的插件包，验证 App 是否拒绝安装。
-   **集成测试**：安装 `xcode-cleaner` 插件，验证是否正确识别 Xcode 缓存路径。

### 效果
-   成功支持了 CapCut、Xcode、Docker 三种清理规则的热插拔。
-   Sys AI Box 配对时间 < 10秒，用户体验流畅。

---

## 11. 可迁移性（macOS → iOS）

-   **插件系统**：完全通用，iOS 端也支持下载 Data Pack。
-   **文件访问**：iOS App 只能访问特定的 Container 或 Group Container，插件规则需针对移动端路径进行适配。

---

## 12. 后续规划（Future Work）

1.  **插件签名**：引入非对称加密签名（Ed25519），除了 Checksum 外，确保插件来源可信。
2.  **Web 交互**：允许 Sys AI Box 返回简单的 HTML/JS 界面，嵌入到 App 的 WebView 中，增强交互性。
3.  **社区插件源**：支持用户添加第三方 URL 作为插件源。

---

## 13. 总结（Takeaways）

本模块展示了如何在受限环境（Sandbox + Hardened Runtime）下构建安全的扩展系统。**Data-Driven Design** 是关键——将逻辑与配置分离。同时，通过标准的 OAuth 2.0 协议实现了优雅的 IoT 设备协同体验，拓展了桌面 App 的边界。
