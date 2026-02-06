#!/bin/bash
# SwiftFormat runner script
# Usage: ./scripts/format.sh [--lint] [--dryrun] [path]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Check if SwiftFormat is installed
if ! command -v swiftformat &> /dev/null; then
  echo "❌ SwiftFormat is not installed"
  echo "Install with: brew install swiftformat"
  echo "Or download from: https://github.com/nicklockwood/SwiftFormat/releases"
  exit 1
fi

echo "🎨 Running SwiftFormat..."
echo "SwiftFormat version: $(swiftformat --version)"

# Parse arguments
LINT_MODE=""
DRYRUN=""
TARGET_PATH="Sources/ Tests/"

for arg in "$@"; do
  case $arg in
    --lint)
      LINT_MODE="--lint"
      shift
      ;;
    --dryrun)
      DRYRUN="--dryrun"
      shift
      ;;
    *)
      if [ -e "$arg" ]; then
        TARGET_PATH="$arg"
        shift
      fi
      ;;
  esac
done

# Run SwiftFormat
if [ -n "$LINT_MODE" ]; then
  echo "Running in lint mode (check only, no changes)..."
  swiftformat $LINT_MODE $TARGET_PATH
elif [ -n "$DRYRUN" ]; then
  echo "Running in dry-run mode (preview changes)..."
  swiftformat $DRYRUN --verbose $TARGET_PATH
else
  echo "Formatting code..."
  swiftformat $TARGET_PATH
fi

echo "✅ SwiftFormat completed"
