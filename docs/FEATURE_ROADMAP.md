# Implementation Plan: SwiftSweep Feature Roadmap / 实施计划

## Overview / 概览

This plan covers five requested features with investigation, fixes, and new capabilities.
中文：本计划覆盖五项需求，包含分析、修复与新能力建设。

1. Helper Installation Fix / Helper 安装修复  
2. Plugins UI Alignment Fix / 插件 UI 对齐修复  
3. Plugin Store / 插件商店  
4. GitHub Pages Website / 官网（GitHub Pages）  
5. Roadmap Timeline / 路线图时间表  

**Guiding Principle / 原则**  
Follow existing design decisions (see `docs/DESIGN_PLUGIN.md`), avoid dynamic code loading unless explicitly approved.
中文：遵循现有设计决策（`docs/DESIGN_PLUGIN.md`），除非明确批准，否则不引入动态代码加载。

---

## 1) Helper Installation Fix / Helper 安装修复

### Problem / 问题
`SMAppService` installation fails with "Operation not permitted".
中文：`SMAppService` 安装失败，报错 Operation not permitted。

### Root Causes / 根因
* Code signing mismatch between app and helper.  
  中文：主程序与 helper 签名不一致。
* Hardened Runtime or entitlements missing.  
  中文：未启用 Hardened Runtime 或缺少 entitlements。
* Helper plist not embedded at `Contents/Library/LaunchDaemons`.  
  中文：helper plist 未正确嵌入路径。
* macOS 13+ requires user approval in Login Items.  
  中文：macOS 13+ 需在登录项中手动批准。

### Plan / 计划
1. **Validate Packaging**: verify helper binary and plist location.  
   中文：验证 helper 二进制与 plist 位置。
2. **Entitlements**: add helper-specific entitlements file.  
   中文：补充 helper 专用 entitlements。
3. **User Guidance**: improve error messaging with clear next steps.  
   中文：优化错误提示，明确引导用户操作。
4. **Login Items Shortcut**: add "Open Login Items" button when approval is required.  
   中文：在需要批准时提供“打开登录项”按钮。

### Acceptance Criteria / 验收标准
* On clean macOS 13+, helper installs or prompts for Login Items approval.  
  中文：在干净的 macOS 13+ 上可正常安装或提示用户批准登录项。
* Error message includes actionable steps.  
  中文：错误提示可执行、可理解。

---

## 2) Plugins UI Alignment Fix / 插件 UI 对齐修复

### Issue / 问题
Sys AI Box rows are visually misaligned with other sections (badges and buttons).
中文：Sys AI Box 区块与其他设置项在对齐、间距上不一致。

### Plan / 计划
Refactor layout into consistent vertical sections:
中文：重构为统一的三行结构。

```swift
VStack(alignment: .leading, spacing: 12) {
  HStack { Text("Sys AI Box"); Spacer(); statusBadges }
  HStack { urlField; testButton }
  HStack { pairButton; openConsoleButton }
}
```

### Acceptance Criteria / 验收标准
* Status badges right-aligned and consistent with other settings rows.  
  中文：状态徽标右对齐且风格一致。
* Buttons align and maintain uniform spacing.  
  中文：按钮对齐，间距统一。

---

## 3) Plugin Store / 插件商店

### Constraint / 约束
`DESIGN_PLUGIN.md` rejects dynamic bundle loading due to Hardened Runtime.
中文：`DESIGN_PLUGIN.md` 明确拒绝动态加载代码。

### Strategy / 策略
* **v1**: Plugin Store ships **data packs** (rules, templates, metadata) rather than executable code.  
  中文：v1 仅提供“数据包”而非可执行插件代码。
* **Code Plugins**: delivered via app updates or precompiled targets.  
  中文：可执行插件通过应用更新或编译期目标提供。

### Architecture / 架构
```
SwiftSweep
  ├── PluginStoreView
  ├── PluginDownloadManager
  ├── PluginManifest (plugins.json)
  └── Plugins (data packs only)
       ~/Library/Application Support/SwiftSweep/Plugins
```

### Manifest Schema / 清单结构
```json
{
  "plugins": [
    {
      "id": "com.swiftsweep.capcut",
      "name": "CapCut Cleaner",
      "version": "1.0.0",
      "description": "Cleans unused CapCut drafts",
      "author": "SwiftSweep Team",
      "minAppVersion": "0.3.0",
      "downloadUrl": "https://github.com/.../CapCut.rules.zip",
      "checksum": "sha256:..."
    }
  ]
}
```

### Plan / 计划
1. **Define Data Pack Format**: JSON + assets, no executable code.  
   中文：定义数据包格式，禁止代码。
2. **Download & Verify**: checksum verification and signature support.  
   中文：下载校验与签名验证。
3. **Install/Remove**: manage under Application Support.  
   中文：安装/卸载管理。
4. **UI**: PluginStoreView for browse/install/update.  
   中文：插件商店 UI。

### Acceptance Criteria / 验收标准
* Data pack install/uninstall works end-to-end.  
  中文：数据包可完整安装/卸载。
* No dynamic code loading introduced.  
  中文：不引入动态代码加载。

---

## 4) GitHub Pages Website / 官网（GitHub Pages）

### Scope / 范围
Static marketing website with docs.
中文：静态官网与文档站点。

### Structure / 目录
```
/
├── index.html
├── features.html
├── plugins.html
├── docs/
│   ├── getting-started.md
│   ├── plugin-development.md
│   └── api-reference.md
├── assets/
│   ├── css/
│   ├── js/
│   └── images/
└── _config.yml
```

### Design Direction / 视觉方向
Clean macOS utility aesthetic (similar to CleanMyMac, AppCleaner, Bartender).
中文：参考 macOS 工具类产品的简洁风格。

### Deployment Options / 部署方式
* **Primary**: GitHub Pages (CI/CD optional).  
  中文：优先使用 GitHub Pages。
* **Optional Self-Host**: Deploy the same static site to a remote server (Nginx).  
  中文：可选自托管到远程服务器（Nginx）。
  * Target host can be a dedicated server (e.g., `ssh ubuntu@106.54.188.236`).  
    中文：目标可为独立服务器（例如 `ssh ubuntu@106.54.188.236`）。
  * Use SSH key-based auth; do not store credentials in repo.  
    中文：使用 SSH Key，不在仓库内保存凭证。

---

## 5) Roadmap Timeline / 路线图时间表

### Calendar / 日期安排
* 2026-01-03: Helper Fix  
* 2026-01-05: Plugins UI Fix  
* 2026-01-07: Plugin Store Design  
* 2026-01-09: Plugin Store Implementation  
* 2026-01-11: GitHub Pages Setup  
* 2026-01-13: Website Content  
* 2026-01-15: Plugin Ecosystem  
* 2026-01-17: Phase 1 Complete  
* 2026-01-19: Phase 2 Complete  
* 2026-01-21: Phase 3 Complete  
* 2026-01-23: Phase 4 Complete  
* 2026-01-25: SwiftSweep Feature Roadmap Review  

### Phase Summary / 阶段总结
| Phase | Duration | Items |
| --- | --- | --- |
| Phase 1 | 2 days | Helper fix, UI alignment |
| Phase 2 | 8 days | Plugin store design + implementation |
| Phase 3 | 7 days | GitHub Pages website |
| Phase 4 | 5 days | Plugin ecosystem (docs, SDK, examples) |

---

## Verification Plan / 验证计划

* **Helper**: Test on clean macOS 13+, verify Login Items approval flow.  
  中文：在干净的 macOS 13+ 上验证安装与批准流程。
* **UI**: Visual inspection + screenshot comparison.  
  中文：视觉检查与截图对比。
* **Plugin Store**: End-to-end install/uninstall flow.  
  中文：插件数据包端到端安装/卸载验证。
* **Website**: Mobile/desktop responsiveness, SEO basics.  
  中文：移动端/桌面端适配与 SEO 基础检查。

---

## Open Questions / 待确认

* Should we ever allow dynamic code plugins, or keep data-only packs?  
  中文：是否允许动态代码插件，还是仅数据包？
* Do we need a signed manifest and key rotation policy for the plugin registry?  
  中文：插件清单是否需要签名与密钥轮换策略？
* For self-hosted website, do we need CDN or just static Nginx?  
  中文：自托管是否需要 CDN？
