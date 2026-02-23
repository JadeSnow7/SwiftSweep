#!/bin/bash
# ci_post_clone.sh - 在 Xcode Cloud 克隆仓库后立即运行
# 用于生成 XcodeGen 管理的 .xcodeproj 文件

set -euo pipefail

echo "=== ci_post_clone.sh ==="
echo "Script directory: $(pwd)"

# 切换到项目根目录 (ci_scripts 的父目录)
cd "$(dirname "$0")/.."
echo "Project root: $(pwd)"

# 安装 XcodeGen (如果需要)
if ! command -v xcodegen &> /dev/null; then
    echo "Installing XcodeGen via Homebrew..."
    HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
else
    echo "XcodeGen already installed: $(xcodegen --version)"
fi

# 生成 Xcode 项目
echo "Generating Xcode project from project.yml..."
xcodegen generate

# 验证
if [ -d "SwiftSweepDevID.xcodeproj" ]; then
    echo "✅ SwiftSweepDevID.xcodeproj generated successfully"
else
    echo "❌ Failed to generate xcodeproj"
    exit 1
fi

# 解决包依赖 (跳过已解析文件要求)
echo "Resolving Swift Package dependencies..."
xcodebuild -resolvePackageDependencies \
    -project SwiftSweepDevID.xcodeproj \
    -scheme SwiftSweepApp || echo "Package resolution completed with warnings"

if [[ -x "./ci_scripts/xcode_cloud_workflow_doctor.sh" ]]; then
    echo "Running Xcode Cloud workflow preflight..."
    ./ci_scripts/xcode_cloud_workflow_doctor.sh preflight || true
fi

echo "=== ci_post_clone.sh completed ==="
