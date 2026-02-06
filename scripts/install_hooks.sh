#!/bin/bash
# Install pre-commit hooks for SwiftSweep
# Usage: ./scripts/install_hooks.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "🪝 Installing pre-commit hooks for SwiftSweep"
echo "============================================="
echo ""

# Check if pre-commit is installed
if ! command -v pre-commit &> /dev/null; then
  echo "❌ pre-commit is not installed"
  echo ""
  echo "Install with:"
  echo "  pip3 install pre-commit"
  echo ""
  echo "Or run: ./scripts/install_tools.sh"
  exit 1
fi

echo "✅ pre-commit found ($(pre-commit --version))"

# Check if SwiftLint is installed
if ! command -v swiftlint &> /dev/null; then
  echo "⚠️  SwiftLint is not installed"
  echo "   Run: brew install swiftlint"
  echo ""
fi

# Check if SwiftFormat is installed
if ! command -v swiftformat &> /dev/null; then
  echo "⚠️  SwiftFormat is not installed"
  echo "   Run: brew install swiftformat"
  echo ""
fi

# Install hooks
echo ""
echo "Installing hooks..."
pre-commit install

# Run hooks on all files to verify setup
echo ""
echo "Testing hooks on all files..."
if pre-commit run --all-files; then
  echo ""
  echo "============================================="
  echo "✅ Pre-commit hooks installed successfully!"
  echo ""
  echo "Hooks will run automatically on 'git commit'"
  echo "To skip hooks, use: git commit --no-verify"
  echo ""
else
  echo ""
  echo "============================================="
  echo "⚠️  Some hooks failed, but installation is complete"
  echo ""
  echo "Fix the issues above and commit again"
  echo "Or run: pre-commit run --all-files"
  echo ""
fi
