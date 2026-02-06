#!/bin/bash
# Generate DocC documentation for SwiftSweepCore
# Usage: ./scripts/generate_docs.sh [--static]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "📚 Generating DocC Documentation"
echo "================================="
echo ""

# Parse arguments
STATIC_HOSTING=""

for arg in "$@"; do
  case $arg in
    --static)
      STATIC_HOSTING="true"
      shift
      ;;
  esac
done

# Clean previous documentation
echo "🧹 Cleaning previous documentation..."
rm -rf .build/documentation
rm -rf docs/api

# Generate documentation
echo ""
echo "📖 Generating documentation..."

if [ "$STATIC_HOSTING" = "true" ]; then
  echo "Generating for static hosting (GitHub Pages)..."

  # Generate with static hosting transform
  swift package \
    --allow-writing-to-directory docs/api \
    generate-documentation \
    --target SwiftSweepCore \
    --output-path docs/api \
    --transform-for-static-hosting \
    --hosting-base-path SwiftSweep

  echo ""
  echo "✅ Static documentation generated: docs/api/"
  echo ""
  echo "To deploy to GitHub Pages:"
  echo "  1. Commit docs/api/ to your repository"
  echo "  2. Enable GitHub Pages in repository settings"
  echo "  3. Set source to 'main' branch, '/docs' folder"
  echo "  4. Documentation will be available at:"
  echo "     https://[username].github.io/SwiftSweep/documentation/swiftsweepcore/"

else
  echo "Generating for local preview..."

  # Generate for local preview
  swift package generate-documentation \
    --target SwiftSweepCore

  # Find the generated documentation
  DOCC_ARCHIVE=$(find .build -name "SwiftSweepCore.doccarchive" | head -n 1)

  if [ -z "$DOCC_ARCHIVE" ]; then
    echo "❌ Documentation archive not found"
    exit 1
  fi

  echo ""
  echo "✅ Documentation generated: $DOCC_ARCHIVE"
  echo ""
  echo "To preview documentation:"
  echo "  1. Open Xcode"
  echo "  2. Go to Product → Build Documentation"
  echo "  3. Or run: open $DOCC_ARCHIVE"
  echo ""
  echo "To generate for static hosting, run:"
  echo "  ./scripts/generate_docs.sh --static"
fi

echo ""
echo "================================="
echo "✅ Documentation generation complete!"
