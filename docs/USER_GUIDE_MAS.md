# SwiftSweepMAS 审核 / 使用说明（macOS）

面向 Mac App Store 审核与用户的快速使用指引，覆盖可见功能、权限行为与验证路径。

## 产品定位与范围
- Finder 集成的磁盘空间分析工具；仅读取用户选定目录的元数据与体积，不执行删除、清理或系统优化。
- 应用清单（App Inventory）：列出已安装应用，提供筛选、分类与大小估算；需用户授权 `/Applications` 才能计算精确大小。
- 无网络请求、无常驻后台进程；数据存储于 App Group `group.com.swiftsweep.mas` 下的沙盒内。

## 快速上手
1) 启动 App，按引导页完成 3 步：欢迎 → 通知权限（可选）→ 开始使用。  
2) 在侧边栏选择 **Authorized Folders**，通过系统文件选择器添加要分析的目录（建议 `/Applications`、`~/Documents` 等）。  
3) 打开 **System Settings → Privacy & Security → Extensions → Finder Extensions**，勾选 **SwiftSweep** 以启用右键菜单。  
4) Finder 中右键已授权目录 → `SwiftSweep → Analyze`，等待本地分析完成并收到通知，点击通知可回到结果页。  
5) 侧边栏进入 **Applications**：如需精确大小，点击授权按钮选取 `/Applications`；可按「Large / Unused / Recently Updated / Uncategorized」筛选，并为应用分组。  
6) 设置页可开关通知、查看已授权目录，卸载 App 后所有缓存会随沙盒清除。

## 核心功能说明
- **Finder 分析**：仅在用户授权的目录显示菜单；分析结果包含文件夹容量、Top 大文件列表，只读展示。  
- **App Inventory**：展示应用图标、版本、安装/修改时间；支持智能筛选与手动分类；右键仅支持「打开」与「在 Finder 中显示」，不提供卸载。  
- **数据与缓存**：授权书签与分类偏好存于 App Group；深度扫描缓存仅用于加速后续查询，可在重装后清空。  
- **权限行为**：  
  - 文件访问：通过 `fileImporter` 由用户逐项授权；路径严格校验为用户选定目录（扫描 `/Applications` 时要求精确匹配）。  
  - 通知（可选）：用于回传 Finder 分析结果；拒绝后仍可在主界面查看结果。  
  - App Group：仅用于主 App 与 Finder Extension 共享授权和偏好。

## 审核验证路径（建议）
1) 首次启动完成引导并允许通知（可选）。  
2) 在 **Authorized Folders** 添加 `/Applications`。  
3) 系统设置中启用 Finder 扩展。  
4) Finder 右键 `/Applications` → Analyze，查看通知并点击进入结果页（展示总占用与大文件列表）。  
5) 打开 **Applications** 视图，授权 `/Applications` 后查看应用列表与筛选标签；确认无「卸载/删除」操作。  
6) 关闭网络后重复分析，验证功能完全离线。

## 已知限制与预期行为
- 无删除、卸载、清理或系统优化动作；若 Spotlight 不可用，会退回文件枚举，扫描耗时可能增加。  
- 若用户未授权目录或撤销权限，对应菜单会隐藏/失效，提示用户重新授权。  
- Finder 菜单不出现时，可在系统设置中关闭/重新开启扩展以刷新。
