#!/bin/bash
# Install code quality tools for SwiftSweep
# Usage: ./scripts/install_tools.sh

set -e

echo "🚀 Installing SwiftSweep Code Quality Tools"
echo "==========================================="
echo ""

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
  echo "❌ Homebrew is not installed"
  echo "Install from: https://brew.sh"
  exit 1
fi

echo "✅ Homebrew found"

# Install SwiftLint
echo ""
echo "📦 Installing SwiftLint..."
if command -v swiftlint &> /dev/null; then
  echo "✅ SwiftLint already installed ($(swiftlint version))"
else
  brew install swiftlint
  echo "✅ SwiftLint installed ($(swiftlint version))"
fi

# Install SwiftFormat
echo ""
echo "📦 Installing SwiftFormat..."
if command -v swiftformat &> /dev/null; then
  echo "✅ SwiftFormat already installed ($(swiftformat --version))"
else
  brew install swiftformat
  echo "✅ SwiftFormat installed ($(swiftformat --version))"
fi

# Install pre-commit (optional)
echo ""
echo "📦 Installing pre-commit (optional)..."
if command -v pre-commit &> /dev/null; then
  echo "✅ pre-commit already installed ($(pre-commit --version))"
else
  if command -v pip3 &> /dev/null; then
    pip3 install pre-commit
    echo "✅ pre-commit installed ($(pre-commit --version))"
  else
    echo "⚠️  pip3 not found, skipping pre-commit installation"
    echo "   Install Python 3 to use pre-commit hooks"
  fi
fi

echo ""
echo "==========================================="
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Run './scripts/lint.sh' to check code quality"
echo "  2. Run './scripts/format.sh --lint' to check formatting"
echo "  3. Run './scripts/install_hooks.sh' to set up pre-commit hooks"
echo ""
