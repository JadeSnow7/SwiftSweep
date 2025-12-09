# MoleKit - Professional macOS System Optimizer

完全使用 Swift 编写的现代 macOS 系统优化工具。

## 项目特性

- 🎨 **原生 SwiftUI** - 美观的 macOS 用户界面
- ⚡ **高性能** - 直接系统 API 调用
- 📦 **模块化架构** - 易于扩展和维护
- 🔄 **Swift 全栈** - 统一语言栈（GUI + CLI + 核心库）
- 🏆 **生产级代码** - 完整的错误处理和日志

## 快速开始

### 构建

```bash
cd /Users/huaodong/MoleKit
swift build
```

### 运行 GUI 应用

```bash
swift run MoleKitUI
```

### 运行 CLI 工具

```bash
swift run molekit status
swift run molekit clean --dry-run
swift run molekit analyze
```

## 项目结构

```
MoleKit/
├── Sources/
│   ├── MoleKitCore/          # 核心逻辑库
│   │   ├── CleanupEngine/    # 清理引擎
│   │   ├── AnalyzerEngine/   # 分析引擎
│   │   ├── SystemMonitor/    # 系统监控
│   │   └── OptimizationEngine/ # 优化引擎
│   ├── MoleKitCLI/           # 命令行工具
│   └── MoleKitUI/            # GUI 应用
├── Tests/                     # 测试套件
└── Package.swift             # Swift Package 配置
```

## 模块说明

### MoleKitCore
核心功能库，包含所有系统操作逻辑：
- `CleanupEngine` - 文件扫描、清理、删除
- `AnalyzerEngine` - 磁盘空间分析
- `SystemMonitor` - 实时系统监控
- `OptimizationEngine` - 系统优化

### MoleKitCLI
命令行工具，使用 Swift Argument Parser：
```bash
molekit clean [--dry-run] [--whitelist]
molekit analyze [--show-large]
molekit optimize [--list]
molekit status [--json]
```

### MoleKitUI
原生 SwiftUI 应用，支持：
- 系统实时监控
- 深度清理扫描
- 磁盘空间分析
- 应用卸载管理

## 开发路线图

- [ ] Phase 1: CleanupEngine 完整实现
- [ ] Phase 2: SystemMonitor 完整实现
- [ ] Phase 3: GUI 应用完善
- [ ] Phase 4: CLI 工具集成
- [ ] Phase 5: 测试覆盖
- [ ] Phase 6: v1.0 发布

## 系统要求

- macOS 13.0+
- Swift 5.9+
- Apple Silicon 或 Intel 处理器

## 许可证

MIT License

## 致谢

基于 Mole 原始项目的架构和设计理念。
