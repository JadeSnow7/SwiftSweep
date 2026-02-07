# Xcode Cloud Workflow 配置（SwiftSweep）

SwiftSweep 采用 **Developer ID（独立分发，DMG + Notarize）** 发布方式：仓库根目录的 `Package.swift` + `scripts/build_universal.sh`（由 `ci_scripts` 在 Xcode Cloud 中产出 DMG Artifact 并可选自动公证）。
DMG 由 `scripts/create_dmg.sh` 统一生成，默认包含 `/Applications` 软链接用于拖拽安装引导。

> 说明：Xcode Cloud 的 workflow 本身在 App Store Connect/Xcode 里配置，不会像 GitHub Actions 一样"完全落在仓库文件里"。本仓库提供的是 **Xcode Cloud 可识别的自定义脚本（`ci_scripts/`）** + 一套推荐的 workflow 配置清单。

---

## 1) 通用前置条件

- 你的 App 已在 **App Store Connect** 创建（至少有一个 App Record）。
- 你在 Xcode 登录了对应的 Apple ID，并能访问对应 Team。
- 需要跑的 scheme 已 **Shared**（本仓库已包含 `xcshareddata/xcschemes`）。

---

## 2) Developer ID（SwiftSweepDevID）推荐 Workflow（产出 DMG + Notarize）

目标：Archive 后自动 **导出 DMG**，并（可选）自动 **Notarize + Staple**，最终把 DMG 作为 Xcode Cloud Artifact。

### 2.1 在 Xcode 创建 Workflow

1. 用 Xcode 打开仓库根目录的 `Package.swift`
2. `Product` → `Xcode Cloud` → `Create Workflow`
3. Workflow 选择：
   - **Scheme**：`SwiftSweepApp`（或任意能跑通的 scheme）
   - **Action**：建议用 `Build`（脚本会自己跑 `scripts/build_universal.sh`；不需要 archive）
4. Triggers 建议（二选一）：
   - `On Push`：`main`（频繁产物，适合内部测试）
   - `On Tag`：`v*`（更像 GitHub Actions 的 release）

### 2.2 打开/关闭 DMG & Notary（关键）

本仓库提供的脚本：`ci_scripts/ci_post_xcodebuild.sh`  
它默认 **不做任何事**，只有在 workflow 环境变量开启后才会运行。

在 Xcode Cloud 的 workflow → Environment Variables 里添加：

- `SWIFTSWEEP_CI_EXPORT_DMG=1`（开启 DMG 导出）
- `SWIFTSWEEP_CI_NOTARIZE=1`（开启 Notarize + Staple；可先不加，先跑通 DMG）
- `SWIFTSWEEP_CI_NOTARIZE_REQUIRED=1`（可选：当开启 Notarize 但未配置凭据时强制失败；默认仅告警并跳过）
- `SWIFTSWEEP_CI_SPM_BUILD=1`（当 workflow 动作为 `Build`/`Test` 时必须开启；脚本会走 SwiftPM 打包路径）
- `SWIFTSWEEP_CI_UPLOAD_RELEASE=1`（可选：把 DMG 与 sha256 上传到 GitHub Release）

可选变量：

- `SWIFTSWEEP_APP_NAME=SwiftSweep`（脚本会先按该名称找 `.app`；找不到会自动从 archive 里探测）
- `SWIFTSWEEP_OUTPUT_NAME=SwiftSweep`（产物命名；当 archive 里的 `.app` 名称不是你想要的名字时使用）
- `SIGNING_IDENTITY=Developer ID Application: ...`（可不填；脚本会尝试自动找第一个 Developer ID identity）
- `SWIFTSWEEP_CI_RELEASE_REPO=owner/repo`（可选：默认从 `origin` 自动解析）
- `SWIFTSWEEP_CI_RELEASE_TAG=v1.7.2`（可选：默认从当前 tag/HEAD 自动解析）
- `GH_TOKEN` 或 `GITHUB_TOKEN`（当 `SWIFTSWEEP_CI_UPLOAD_RELEASE=1` 时必填）

### 2.3 配置 Developer ID 证书（Secrets）

Xcode Cloud 环境里如果没有可用的 `Developer ID Application` 证书，Xcode 在签名阶段会回落到其他证书/或直接失败，导致公证报错。

本仓库提供的脚本：`ci_scripts/ci_pre_xcodebuild.sh`  
会在 `xcodebuild` 之前把证书导入 keychain（优先使用 Xcode Cloud 的 `CI_KEYCHAIN_PATH`）。

在 workflow → Environment Variables（Secrets）里添加：

- `MACOS_CERTIFICATE`：Developer ID 证书 `.p12` 的 base64
- `MACOS_CERTIFICATE_PWD`：该 `.p12` 的导出密码

### 2.4 配置 Notarize 凭证（Secrets）

脚本支持两套方式，推荐优先用 **App Store Connect API Key**（更适合 CI）：

**方式 A（推荐）：App Store Connect API Key**

- `NOTARY_KEY_ID`
- `NOTARY_ISSUER_ID`
- `NOTARY_PRIVATE_KEY_BASE64`（把 `.p8` 文件内容做 base64 后填入）

**方式 B：Apple ID + App 专用密码**

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`（App-Specific Password）

### 2.5 产物位置

脚本会把产物写到：

- `$CI_ARTIFACTS_PATH/<SWIFTSWEEP_OUTPUT_NAME>.dmg`
- `$CI_ARTIFACTS_PATH/<SWIFTSWEEP_OUTPUT_NAME>.dmg.sha256`

在 Xcode Cloud 的 build 页面里可直接下载。

### 2.6 自动上传 GitHub Release（可选）

当 `SWIFTSWEEP_CI_UPLOAD_RELEASE=1` 时，`ci_scripts/ci_post_xcodebuild.sh` 会：

1. 确认/创建对应 tag 的 GitHub Release；
2. 上传 `<name>.dmg` 与 `<name>.dmg.sha256`（同名会覆盖）；
3. 输出 release URL 到日志。

如果当前构建不是 tag（且未设置 `SWIFTSWEEP_CI_RELEASE_TAG`），脚本会输出提示并跳过上传，不会让构建失败。

建议搭配 Tag 触发（`v*`）使用，避免在普通 push 上误发 release。

---

## 3) 常见问题

- **脚本报 "CI_ARCHIVE_PATH is not set"**：用 `Build/Test` 动作时请设置 `SWIFTSWEEP_CI_SPM_BUILD=1`；或改用 `Archive` 动作。
- **找不到 Developer ID 签名身份**：在 workflow 里显式设置 `SIGNING_IDENTITY`，或确认 Xcode Cloud 环境里有可用的 Developer ID 证书。
- **Notarytool 鉴权失败**：优先改用方式 A（API Key）；方式 B 需要开启 2FA 并使用 App 专用密码。
