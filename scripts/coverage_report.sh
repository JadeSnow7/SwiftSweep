#!/bin/bash
# Generate code coverage report for SwiftSweep
# Usage: ./scripts/coverage_report.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "📊 Generating Code Coverage Report"
echo "==================================="
echo ""

# Check if lcov is installed
if ! command -v lcov &> /dev/null; then
  echo "⚠️  lcov is not installed (optional, for HTML reports)"
  echo "   Install with: brew install lcov"
  echo ""
fi

# Clean previous coverage data
echo "🧹 Cleaning previous coverage data..."
rm -rf .build/debug/codecov
rm -f lcov.info
rm -rf coverage_html

# Run tests with coverage
echo ""
echo "🧪 Running tests with coverage..."
swift test --enable-code-coverage

# Find coverage data
echo ""
echo "📈 Processing coverage data..."
PROFDATA_PATH=$(find .build -name "*.profdata" | head -n 1)

if [ -z "$PROFDATA_PATH" ]; then
  echo "❌ No coverage data found"
  exit 1
fi

echo "Found coverage data: $PROFDATA_PATH"

# Get list of test binaries
TEST_BINARIES=$(find .build -name "SwiftSweepPackageTests.xctest" -o -name "*.xctest" | head -n 1)

if [ -z "$TEST_BINARIES" ]; then
  # Try to find the test binary directly
  TEST_BINARIES=$(find .build/debug -type f -name "SwiftSweepPackageTests" | head -n 1)
fi

if [ -z "$TEST_BINARIES" ]; then
  echo "❌ No test binaries found"
  exit 1
fi

echo "Using test binary: $TEST_BINARIES"

# Generate coverage report
echo ""
echo "📋 Coverage Summary:"
echo "-------------------"
xcrun llvm-cov report \
  "$TEST_BINARIES" \
  -instr-profile="$PROFDATA_PATH" \
  -ignore-filename-regex=".build|Tests" \
  -use-color

# Generate lcov format if lcov is installed
if command -v lcov &> /dev/null; then
  echo ""
  echo "📄 Generating lcov.info..."
  xcrun llvm-cov export \
    "$TEST_BINARIES" \
    -instr-profile="$PROFDATA_PATH" \
    -ignore-filename-regex=".build|Tests" \
    -format=lcov > lcov.info

  echo "📊 Generating HTML report..."
  genhtml lcov.info \
    --output-directory coverage_html \
    --title "SwiftSweep Code Coverage" \
    --legend \
    --quiet

  echo ""
  echo "✅ HTML report generated: coverage_html/index.html"
  echo "   Open with: open coverage_html/index.html"
fi

echo ""
echo "==================================="
echo "✅ Coverage report complete!"
