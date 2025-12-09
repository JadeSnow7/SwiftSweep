# MoleKit 完整迁移指南

## 📋 项目现状

已完成：
- ✅ 新项目结构创建 (`/Users/huaodong/MoleKit`)
- ✅ Swift Package 配置完成
- ✅ 项目架构设计
- ✅ 核心框架骨架
- ✅ CLI 工具框架
- ✅ GUI 应用框架

## 🚀 快速启动

### 1. 验证项目结构

```bash
cd /Users/huaodong/MoleKit
tree -L 3
```

### 2. 构建项目

```bash
swift build
```

### 3. 测试 CLI

```bash
swift run molekit status
```

## 🔄 分阶段迁移计划

### 第一阶段：Status 功能迁移（优先级 1）

**目标**：将现有 `status-go` 的功能完整迁移到 Swift

**任务**：
1. 在 `SystemMonitor.swift` 中实现系统指标获取
   - CPU 使用率获取
   - 内存信息获取
   - 磁盘信息获取
   - 电池状态获取
   - 网络速度获取

2. 在 `MoleKitUI` 中完善 Status 页面
   - 显示系统指标卡片
   - 实时更新
   - CPU 核心详情
   - Top Processes 列表

3. 在 `MoleKitCLI` 中实现 status 命令
   - 支持 `--json` 输出
   - 支持 `--watch` 模式

**预计时间**：4-6 小时

---

### 第二阶段：Clean 功能迁移（优先级 2）

**目标**：将 `bin/clean.sh` 和相关脚本完全迁移

**任务**：
1. 在 `CleanupEngine.swift` 中实现扫描逻辑
   - 用户缓存扫描
   - 浏览器缓存扫描
   - 系统缓存扫描
   - 日志清理
   - 白名单管理

2. 在 `MoleKitUI` 中完善 Clean 页面
   - 扫描流程展示
   - 项目选择和预览
   - 执行清理
   - 结果统计

3. 在 `MoleKitCLI` 中实现 clean 命令
   - 支持 `--dry-run`
   - 支持 `--whitelist` 管理

**预计时间**：6-8 小时

---

### 第三阶段：Analyze 功能迁移（优先级 3）

**目标**：将磁盘分析功能迁移到 Swift

**任务**：
1. 实现 `AnalyzerEngine`
   - 目录树遍历
   - 大文件检测
   - 空间占用计算

2. 完善 GUI Analyze 页面
   - 磁盘概览
   - 目录浏览
   - 大文件列表

3. 实现 CLI analyze 命令

**预计时间**：4-6 小时

---

### 第四阶段：Optimize 功能迁移（优先级 4）

**目标**：实现系统优化功能

**任务**：
1. 实现 `OptimizationEngine`
   - 缓存重建
   - 服务优化
   - 清理临时文件

2. 完善 GUI Optimize 页面

3. 实现 CLI optimize 命令

**预计时间**：3-5 小时

---

### 第五阶段：Uninstall 功能迁移（优先级 5）

**目标**：实现应用智能卸载功能

**任务**：
1. 扫描已安装应用
2. 追踪应用相关文件
3. 安全卸载和清理

**预计时间**：3-4 小时

---

## 📦 代码复用策略

### 从现有项目移植

```swift
// 从 Go 代码移植到 Swift
// cmd/status/main.go -> MoleKitCore/SystemMonitor/

// 从 Shell 脚本移植到 Swift
// bin/clean.sh -> MoleKitCore/CleanupEngine/

// 从 lib/ 移植到 Swift
// lib/core/*.sh -> MoleKitCore/
```

### 调用现有二进制（过渡方案）

在完全迁移前，可以继续调用现有的 Go 二进制：

```swift
// 临时方案：调用 status-go
import Foundation

func getStatusViaGoBinary() async -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", "script -q /dev/null /path/to/status-go | head -n 200"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
```

## 🛠️ 开发建议

### 1. 使用现有的 desktop/MoleApp 代码

已完成的代码可以直接迁移：
- `CleanView.swift` → `MoleKit/Sources/MoleKitUI/Views/CleanView.swift`
- `StatusView.swift` → `MoleKit/Sources/MoleKitUI/Views/StatusView.swift`

```bash
# 复制现有代码
cp /Users/huaodong/Mole/desktop/MoleApp/Sources/MoleApp/Views/CleanView.swift \
   /Users/huaodong/MoleKit/Sources/MoleKitUI/Views/

cp /Users/huaodong/Mole/desktop/MoleApp/Sources/MoleApp/Core/ShellRunner.swift \
   /Users/huaodong/MoleKit/Sources/MoleKitCore/Utils/
```

### 2. 测试策略

```swift
// Tests/MoleKitTests/CleanupEngineTests.swift
import XCTest
import MoleKitCore

class CleanupEngineTests: XCTestCase {
    func testScanForCleanableItems() async throws {
        let engine = CleanupEngine.shared
        let items = try await engine.scanForCleanableItems()
        XCTAssertGreater(items.count, 0)
    }
}
```

### 3. 性能优化

- 使用 `async/await` 处理长时间操作
- 后台线程执行 I/O 操作
- 缓存文件系统信息

### 4. 安全考虑

- 完整的错误处理
- 权限验证
- 用户确认机制
- 操作日志记录

## 📝 检查清单

### 项目设置
- [ ] Swift Package 正确配置
- [ ] 所有依赖已安装
- [ ] 代码能正常编译

### 功能迁移
- [ ] Status 功能完成
- [ ] Clean 功能完成
- [ ] Analyze 功能完成
- [ ] Optimize 功能完成
- [ ] Uninstall 功能完成

### 质量保证
- [ ] 单元测试覆盖 > 70%
- [ ] 集成测试通过
- [ ] 性能基准测试
- [ ] macOS 兼容性测试

### 发布准备
- [ ] 代码审查
- [ ] 用户文档
- [ ] 安装指南
- [ ] 变更日志

## 🎯 下一步行动

1. **立即开始** Phase 1 (Status 迁移)
2. **并行准备** Phase 2 的需求分析
3. **定期同步** 迁移进度

## 📧 需要帮助？

如遇到技术问题，参考：
- [Swift Documentation](https://swift.org/documentation)
- [macOS App Development](https://developer.apple.com/mac)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/SwiftUI)
