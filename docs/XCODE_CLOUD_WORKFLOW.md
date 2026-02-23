# Xcode Cloud Workflow 配置（SwiftSweep）

SwiftSweep 使用 Developer ID 直发（DMG + Notarize）。
Xcode Cloud workflow 需要在 App Store Connect / Xcode UI 里配置，本仓库提供以下可直接使用的脚本与模板：

- `ci_scripts/ci_post_clone.sh`
- `ci_scripts/ci_pre_xcodebuild.sh`
- `ci_scripts/ci_post_xcodebuild.sh`
- `ci_scripts/xcode_cloud_workflow_doctor.sh`
- `ci_scripts/xcode_cloud.env.template`

---

## 1) 前置条件

- App Store Connect 中已创建 App Record。
- Xcode 已登录对应 Team。
- Shared scheme 存在（仓库已包含 `xcshareddata/xcschemes`）。

---

## 2) 创建 Workflow（推荐）

### 2.1 Build Workflow（主线 CI）

1. 打开仓库内 `Package.swift`。
2. `Product -> Xcode Cloud -> Create Workflow`。
3. 建议配置：
- Scheme: `SwiftSweepApp`
- Action: `Build`
- Trigger: `On Push`，分支 `main`

### 2.2 Release Workflow（发布）

1. 复制 Build workflow。
2. Trigger 改为 `On Tag`，规则 `v*`。
3. 保持 Scheme/Action 不变。

说明：`ci_scripts/` 下的标准脚本会被 Xcode Cloud 自动识别执行。

---

## 3) Environment Variables（非 Secret）

先按 `ci_scripts/xcode_cloud.env.template` 配置，至少需要：

- `SWIFTSWEEP_CI_EXPORT_DMG=1`
- `SWIFTSWEEP_CI_SPM_BUILD=1`（Build/Test 动作必须）
- `SWIFTSWEEP_OUTPUT_NAME=SwiftSweep`

可选：

- `SWIFTSWEEP_CI_NOTARIZE=1`
- `SWIFTSWEEP_CI_NOTARIZE_REQUIRED=1`
- `SWIFTSWEEP_CI_UPLOAD_RELEASE=1`
- `SWIFTSWEEP_CI_RELEASE_REPO=owner/repo`
- `SWIFTSWEEP_CI_RELEASE_TAG=v1.7.2`
- `SWIFTSWEEP_CI_DOCTOR_STRICT=1`（doctor 发现错误时直接 fail）

---

## 4) Secrets

### 4.1 Developer ID 证书

- `MACOS_CERTIFICATE` (p12 base64)
- `MACOS_CERTIFICATE_PWD`

`ci_pre_xcodebuild.sh` 会自动导入 keychain。

### 4.2 公证凭据（二选一）

方式 A（推荐，API Key）：

- `NOTARY_KEY_ID`
- `NOTARY_ISSUER_ID`
- `NOTARY_PRIVATE_KEY_BASE64`

方式 B（Apple ID）：

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

### 4.3 GitHub Release（可选）

- `GH_TOKEN` 或 `GITHUB_TOKEN`

---

## 5) 产物与检查

产物输出：

- `$CI_ARTIFACTS_PATH/<name>.dmg`
- `$CI_ARTIFACTS_PATH/<name>.dmg.sha256`

预检：

- `ci_post_clone.sh` 会运行 `xcode_cloud_workflow_doctor.sh preflight`
- `ci_post_xcodebuild.sh` 会运行 `xcode_cloud_workflow_doctor.sh postbuild`

---

## 6) 常见问题

- `CI_ARCHIVE_PATH is not set`: Build/Test 动作下未启用 `SWIFTSWEEP_CI_SPM_BUILD=1`。
- `missing notarization credentials`: 开启了 `SWIFTSWEEP_CI_NOTARIZE=1` 但未配置公证凭据。
- DMG 未签名: 未导入 Developer ID 证书或未设置可用 `SIGNING_IDENTITY`。
