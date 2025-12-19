#!/bin/bash
# ci_post_clone.sh - 在 Xcode Cloud 克隆仓库后立即运行
# 用于生成 XcodeGen 管理的 .xcodeproj 文件

set -euo pipefail

echo "=== ci_post_clone.sh ==="
echo "Working directory: $(pwd)"

# 安装 XcodeGen (如果需要)
if ! command -v xcodegen &> /dev/null; then
    echo "Installing XcodeGen via Homebrew..."
    brew install xcodegen
else
    echo "XcodeGen already installed: $(xcodegen --version)"
fi

# 生成 Xcode 项目
echo "Generating Xcode project from project.yml..."
xcodegen generate

# 验证
if [ -d "SwiftSweepDevID.xcodeproj" ]; then
    echo "✅ SwiftSweepDevID.xcodeproj generated successfully"
    ls -la SwiftSweepDevID.xcodeproj/
else
    echo "❌ Failed to generate xcodeproj"
    exit 1
fi

echo "=== ci_post_clone.sh completed ==="
