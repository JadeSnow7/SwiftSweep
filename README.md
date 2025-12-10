# SwiftSweep

<p align="center">
  <strong>🧹 原生 macOS 系统清理与优化工具</strong>
</p>

<p align="center">
  使用 Swift 和 SwiftUI 构建的现代化系统维护工具
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013+-blue?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.9+-orange?style=flat-square" alt="Swift" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" />
</p>

---

## ✨ 特性

- 🎨 **原生 SwiftUI** — 现代化 macOS 界面，支持暗色模式
- ⚡ **高性能** — 直接调用系统 API，后台线程处理
- 📦 **模块化架构** — CLI + GUI 共享核心逻辑
- 🔐 **智能权限管理** — AppleScript 提权，安全可靠
- 🛡️ **安全至上** — 白名单保护，预览模式 (dry-run)

---

## 🖥️ 界面预览

SwiftSweep 采用两栏式布局，包含以下功能模块：

| 模块 | 功能 |
|------|------|
| **Status** | 系统仪表盘，实时监控 CPU、内存、磁盘 |
| **Clean** | 清理系统缓存、日志、浏览器数据 |
| **Uninstall** | 完整卸载应用及其残留文件 |
| **Optimize** | 系统优化（DNS 刷新、Spotlight 重建等）|
| **Analyze** | 磁盘空间分析，定位大文件 |

---

## 🚀 快速开始

### 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Swift 5.9+
- Apple Silicon 或 Intel 处理器

### 构建与运行

```bash
# 克隆仓库
git clone https://github.com/JadeSnow7/SwiftSweep.git
cd SwiftSweep

# 构建项目
swift build

# 运行 GUI 应用
swift run SwiftSweepApp

# 运行 CLI 工具
swift run swiftsweep --help
```

---

## 📦 项目结构

```
SwiftSweep/
├── Package.swift                 # Swift Package 配置
├── Sources/
│   ├── SwiftSweepCore/           # 核心逻辑库
│   │   ├── CleanupEngine/        # 清理引擎
│   │   ├── UninstallEngine/      # 卸载引擎
│   │   ├── SystemMonitor/        # 系统监控
│   │   ├── AnalyzerEngine/       # 磁盘分析
│   │   ├── OptimizationEngine/   # 系统优化
│   │   └── PrivilegedHelper/     # 权限管理
│   ├── SwiftSweepCLI/            # 命令行工具
│   └── SwiftSweepUI/             # SwiftUI 界面
├── Helper/                       # Privileged Helper 源码
└── Tests/                        # 单元测试
```

---

## 🔧 CLI 使用

```bash
# 查看系统状态
swift run swiftsweep status

# 扫描可清理项（预览模式）
swift run swiftsweep clean --dry-run

# 执行清理
swift run swiftsweep clean

# 磁盘分析
swift run swiftsweep analyze ~/Documents
```

---

## 🛠️ 技术栈

| 组件 | 技术 |
|------|------|
| UI 框架 | SwiftUI |
| CLI 框架 | Swift Argument Parser |
| 日志系统 | swift-log |
| 权限管理 | NSAppleScript / SMAppService |
| 最低系统 | macOS 13.0+ |

---

## 📋 开发路线

- [x] 核心引擎实现 (Cleanup, Uninstall, Analyze, Optimize)
- [x] 系统监控模块 (CPU, 内存, 磁盘, 网络)
- [x] SwiftUI 界面框架
- [x] AppleScript 权限提升
- [ ] SMAppService 完整集成
- [ ] 更多清理规则 (Xcode, Docker, Homebrew)
- [ ] 代码签名与公证

---

## 📄 许可证

MIT License © 2024

---

## 🙏 致谢

本项目的设计理念源自 [Mole](https://github.com/tw93/Mole)，感谢原作者的开源贡献。
