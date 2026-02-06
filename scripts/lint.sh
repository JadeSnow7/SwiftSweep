#!/bin/bash
# SwiftLint runner script
# Usage: ./scripts/lint.sh [--strict] [--autocorrect]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Check if SwiftLint is installed
if ! command -v swiftlint &> /dev/null; then
  echo "❌ SwiftLint is not installed"
  echo "Install with: brew install swiftlint"
  echo "Or download from: https://github.com/realm/SwiftLint/releases"
  exit 1
fi

echo "🔍 Running SwiftLint..."
echo "SwiftLint version: $(swiftlint version)"

# Parse arguments
STRICT_MODE=""
AUTOCORRECT=""

for arg in "$@"; do
  case $arg in
    --strict)
      STRICT_MODE="--strict"
      shift
      ;;
    --autocorrect)
      AUTOCORRECT="true"
      shift
      ;;
  esac
done

# Run autocorrect if requested
if [ "$AUTOCORRECT" = "true" ]; then
  echo "🔧 Auto-correcting violations..."
  swiftlint autocorrect
fi

# Run lint
if [ -n "$STRICT_MODE" ]; then
  echo "Running in strict mode (warnings treated as errors)..."
  swiftlint lint --strict
else
  swiftlint lint
fi

echo "✅ SwiftLint completed"
