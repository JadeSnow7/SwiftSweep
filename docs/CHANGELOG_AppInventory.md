# SwiftSweep 变更与功能文档

## 版本：App Inventory Feature (2024-12-14)

---

## 📦 新增模块：`SwiftSweepAppInventory`

独立的 Swift Package，位于 `Packages/SwiftSweepAppInventory`，提供 MAS 安全的应用程序管理功能。

### 架构设计

| 层级 | 目标 | 依赖 |
|------|------|------|
| `AppInventoryLogic` | 核心逻辑 | Foundation, CoreServices |
| `AppInventoryUI` | SwiftUI 视图 | SwiftUI, AppKit, AppInventoryLogic |

### 核心组件

#### 数据模型 (`Models/`)
- **`AppItem`**: 应用程序数据结构
  - ID (bundleID 或 URL.path)
  - 估算大小 / 精确大小 (可选)
  - 最后使用时间 (可选)
  - 版本、修改时间
  - 数据来源 (Spotlight / FileSystem)

- **`AppCategory`**: 用户自定义分类
- **`CachedAppMetadata`**: 深度扫描缓存结构

#### 存储 (`Storage/`)
- **`OrganizationStore`**: 分类与应用分配持久化 (UserDefaults)
- **`CacheStore`**: 深度扫描结果缓存，支持版本/时间戳失效

#### 扫描 (`Providers/` + `Scanning/`)
- **`InventoryProvider`**: 
  - 主源：NSMetadataQuery (Spotlight)
  - 备用源：FileManager 目录枚举
  - 自动去重：bundleID > 路径长度 > 修改时间

- **`DeepScanner`**:
  - 递归计算 `.app` bundle 的占用空间 (allocated size)
  - 缓存机制，仅重扫变化的应用
  - 支持取消

#### 智能筛选 (`Filters/`)
- 大型应用 (>\500MB)
- 未使用应用 (>90天未启动，如数据可用)
- 最近更新
- 未分类

#### 视图 (`AppInventoryUI`)
- **`AppInventoryViewModel`**: 状态机 + 授权 + 扫描管理
- **`ApplicationsView`**: 网格视图 + 搜索 + 筛选 + 分类管理

---

## 🔄 主分支集成 (`SwiftSweepUI`)

### 新增文件
| 文件 | 说明 |
|------|------|
| `MainApplicationsView.swift` | 桥接 `ApplicationsView` 到 `UninstallEngine` |

### 修改文件
| 文件 | 变更 |
|------|------|
| `Package.swift` | 添加 `SwiftSweepAppInventory` 本地包依赖 |
| `SwiftSweepApp.swift` | 侧边栏新增 "Applications" 导航项 |

### 功能特性
- ✅ 查看已安装应用程序
- ✅ 智能筛选 (大型/未使用/最近更新/未分类)
- ✅ 手动分类管理
- ✅ 右键菜单：打开 / 在 Finder 中显示 / **卸载...**
- ✅ 授权 `/Applications` 后精确计算大小

---

## 🍎 MAS 版本集成 (`SwiftSweepMAS`)

### 修改文件
| 文件 | 变更 |
|------|------|
| `project.yml` | 添加 `SwiftSweepAppInventory` 本地包依赖 |
| `ContentView.swift` | 使用共享 `ApplicationsView`，移除本地实现 (~180 行) |

### 功能特性
- ✅ 查看已安装应用程序
- ✅ 智能筛选
- ✅ 手动分类管理
- ✅ 右键菜单：打开 / 在 Finder 中显示
- ✅ 授权 `/Applications` 后精确计算大小
- ⛔ 卸载功能 (MAS 沙盒限制)

### 沙盒合规
- 使用 App Group (`group.com.swiftsweep.mas`) 存储授权和分类数据
- 深度扫描需用户通过 `fileImporter` 授权 `/Applications`
- 严格校验授权路径 `== "/Applications"`

---

## 📊 功能对比

| 功能 | Main | MAS |
|------|:----:|:---:|
| 查看应用列表 | ✅ | ✅ |
| Spotlight 快速列表 | ✅ | ✅ |
| FileManager 备用列表 | ✅ | ✅ |
| 深度扫描 (精确大小) | ✅ | ✅ |
| 智能筛选 | ✅ | ✅ |
| 手动分类 | ✅ | ✅ |
| 卸载应用 | ✅ | ⛔ |
| 查找残留文件 | ✅ | ⛔ |

---

## 📁 新增文件列表

```
Packages/SwiftSweepAppInventory/
├── Package.swift
└── Sources/
    ├── AppInventoryLogic/
    │   ├── Models/
    │   │   ├── AppItem.swift
    │   │   ├── AppCategory.swift
    │   │   └── CachedAppMetadata.swift
    │   ├── Storage/
    │   │   ├── OrganizationStore.swift
    │   │   └── CacheStore.swift
    │   ├── Providers/
    │   │   └── InventoryProvider.swift
    │   ├── Scanning/
    │   │   └── DeepScanner.swift
    │   └── Filters/
    │       └── SmartFilters.swift
    └── AppInventoryUI/
        ├── AppInventoryViewModel.swift
        └── ApplicationsView.swift

Sources/SwiftSweepUI/
└── MainApplicationsView.swift (新增)
```

---

## ✅ 构建验证

| 目标 | 状态 |
|------|------|
| `swift build --target SwiftSweepUI` | ✅ 成功 |
| `xcodebuild -scheme SwiftSweepMAS` | ✅ 成功 |
