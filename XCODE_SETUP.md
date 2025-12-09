# 将 SwiftSweep 转换为 Xcode 项目

由于 SMJobBless 需要 Xcode 项目结构，请按以下步骤操作：

## 步骤 1: 创建新 Xcode 项目

1. **关闭当前 Package**
2. **File > New > Project**
3. 选择 **macOS > App**
4. 配置:
   - Product Name: `SwiftSweep`
   - Team: 选择您的开发者账号
   - Bundle Identifier: `com.swiftsweep.app`
   - Language: Swift
   - User Interface: SwiftUI
   - ❌ 取消勾选 "Use Core Data"
   - ❌ 取消勾选 "Include Tests"
5. 保存到 `/Users/huaodong/Mole/SwiftSweepXcode`

## 步骤 2: 添加 Helper Target

1. **File > New > Target**
2. 选择 **macOS > Command Line Tool**
3. 配置:
   - Product Name: `com.swiftsweep.helper`
   - Language: Swift
4. 点击 Finish

## 步骤 3: 添加本地 Package

1. **File > Add Package Dependencies**
2. 点击 **Add Local...**
3. 选择 `/Users/huaodong/Mole/MoleKit_Dev`
4. 勾选 `SwiftSweepCore` 添加到 SwiftSweep target

## 步骤 4: 复制源文件

将以下文件复制到新项目:
- `Sources/SwiftSweepUI/*.swift` → SwiftSweep target
- `Helper/*.swift` → com.swiftsweep.helper target
- `Helper/Info.plist` → Helper target
- `Helper/launchd.plist` → Helper target
- `Resources/Info.plist` → 主 App

## 步骤 5: 配置 Helper 嵌入

1. 选择 SwiftSweep target
2. **Build Phases > + > New Copy Files Phase**
3. Destination: **Wrapper**
4. Subpath: `Contents/Library/LaunchServices`
5. 添加 `com.swiftsweep.helper`

## 步骤 6: 配置代码签名

### 主 App (SwiftSweep):
- Signing Certificate: Development 或 Developer ID Application
- 禁用 **Hardened Runtime** 的 "Disable Library Validation"

### Helper (com.swiftsweep.helper):
- Signing Certificate: 同主 App
- 禁用 **Hardened Runtime** 的 "Disable Library Validation"

完成后运行构建，点击 "Install Helper" 按钮测试。
