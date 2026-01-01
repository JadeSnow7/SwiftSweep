# SwiftSweep 开发路线图

## 已完成功能 ✅

### v0.1.0 - 核心功能
- [x] 核心引擎实现 (Cleanup, Uninstall, Analyze, Optimize)
- [x] 系统监控模块 (CPU, 内存, 磁盘, 网络)
- [x] SwiftUI 界面框架
- [x] Smart Insights（智能建议）
- [x] Applications Inventory（应用清单）
- [x] Package Finder（包管理器扫描）
- [x] AppleScript 权限提升
- [x] SMAppService + XPC Helper（基础能力）

### v0.2.0 - 高级分析
- [x] 媒体智能分析（pHash + LSH）
- [x] I/O 性能分析（实时吞吐量/延迟）

### v0.3.0 - 插件化与商业能力 ⭐ NEW
- [x] **插件架构**：`SweepPlugin` 协议 + `PluginManager`
- [x] **CapCut 插件 MVP**：草稿解析与孤儿素材检测
- [x] **商业前端组件**：
  - InsightsAdvancedConfigView（规则分组/优先级/灰度开关）
  - DataGridView（NSTableView 虚拟化，10k+ 行）
  - ResultDashboardView（Swift Charts 趋势图）
- [x] **AI Coding 能力**：
  - SmartInterpreter（证据 → 自然语言解释）
  - NLCommandParser（自然语言 → 过滤条件，中英双语）
  - DecisionGraphView（决策树可视化）
- [x] **体验统一**：
  - UnifiedStorageView（磁盘 + 媒体分析一体化）
  - CleanupHistoryView（清理前后对比）

---

## 进行中 🔄

### v0.4.0 - 生产就绪
- [ ] 代码签名与公证
- [ ] 更多清理规则 (Xcode, Docker, Homebrew)
- [ ] CapCut 插件完善（草稿依赖图、影响分析）

---

## 规划中 📋

### v0.5.0 - 高级诊断
- [ ] 系统级 I/O 追踪（fs_usage/kdebug）
- [ ] 性能热力图 + 异常阈值提示
- [ ] 完善的日志/错误追踪

### v0.6.0 - 云同步与团队
- [ ] iCloud 配置同步
- [ ] 清理报告导出
- [ ] 团队共享规则配置

---

## 面试亮点功能

### 商业前端方向
| 功能 | 文件 | 亮点 |
|------|------|------|
| 规则配置页 | `InsightsAdvancedConfigView.swift` | 分组/拖拽优先级/灰度开关 |
| 虚拟化表格 | `DataGridView.swift` | NSTableView 10k+ 行 |
| 数据看板 | `ResultDashboardView.swift` | Swift Charts 趋势图 |

### AI Coding 方向
| 功能 | 文件 | 亮点 |
|------|------|------|
| 智能解释器 | `SmartInterpreter.swift` | 白盒 AI / 可解释性 |
| 决策图 | `DecisionGraphView.swift` | 证据树可视化 |
| NL 命令解析 | `NLCommandParser.swift` | 规则驱动，中英双语 |
