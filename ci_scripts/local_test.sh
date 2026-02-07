#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_XCODEGEN=0
RUN_CLI_SMOKE=0
RUN_ES_FALLBACK_CHECK=0

usage() {
  cat <<'EOF'
Usage: ./ci_scripts/local_test.sh [--with-xcodegen] [--with-cli-smoke]

  --with-xcodegen   Generate the Xcode project if xcodegen is installed.
  --with-cli-smoke  Run read-only CLI smoke checks.
  --with-es-fallback-check  Run additional tests with SWIFTSWEEP_NO_ENDPOINT_SECURITY.
  -h, --help        Show this help message.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --with-xcodegen) RUN_XCODEGEN=1 ;;
    --with-cli-smoke) RUN_CLI_SMOKE=1 ;;
    --with-es-fallback-check) RUN_ES_FALLBACK_CHECK=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $arg"; usage; exit 1 ;;
  esac
done

cd "$ROOT_DIR"
echo "=== SwiftSweep local test ==="

if [[ "$RUN_XCODEGEN" == "1" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    echo "Generating Xcode project..."
    xcodegen generate
  else
    echo "xcodegen not found; skipping."
  fi
fi

echo "Running unit tests..."
swift test

if [[ "$RUN_ES_FALLBACK_CHECK" == "1" ]]; then
  echo "Running EndpointSecurity fallback check..."
  swift test -Xswiftc -DSWIFTSWEEP_NO_ENDPOINT_SECURITY
fi

if [[ "$RUN_CLI_SMOKE" == "1" ]]; then
  echo "Running CLI smoke checks..."
  swift run swiftsweep status
  swift run swiftsweep peripherals --json
  swift run swiftsweep peripherals --json --sensitive
  swift run swiftsweep diagnostics
  swift run swiftsweep clean --dry-run
fi

echo "=== Local test complete ==="
