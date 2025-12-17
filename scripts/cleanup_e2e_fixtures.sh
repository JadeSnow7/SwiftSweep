#!/bin/bash
set -euo pipefail

# E2E Fixture Cleanup Script
# Removes all test fixtures safely

FIXTURE_ROOT="/Library/Logs/SwiftSweepE2E"
TMP_FIXTURE="/tmp/SwiftSweepE2E"
SENTINEL="$FIXTURE_ROOT/.sentinel"
DMG_DEV_FILE="/tmp/SwiftSweepE2E_dev.txt"

echo "=== SwiftSweep E2E Fixture Cleanup ==="

# DMG cleanup (always attempt)
if [[ -f "$DMG_DEV_FILE" ]]; then
  echo "Detaching DMG..."
  hdiutil detach "$(cat "$DMG_DEV_FILE")" 2>/dev/null || true
fi
rm -f /tmp/SwiftSweepE2E_*.dmg /tmp/SwiftSweepE2E_*.plist /tmp/SwiftSweepE2E_*.txt

# /tmp cleanup (always attempt)
echo "Cleaning /tmp fixtures..."
sudo rm -rf "$TMP_FIXTURE"

# FIXTURE_ROOT cleanup (sentinel + path protected)
if [[ -f "$SENTINEL" && "$FIXTURE_ROOT" == "/Library/Logs/SwiftSweepE2E" ]]; then
  echo "Cleaning FIXTURE_ROOT..."
  sudo chflags -R nouchg "$FIXTURE_ROOT" 2>/dev/null || true
  sudo rm -rf "$FIXTURE_ROOT"
else
  echo "WARN: Sentinel not found or path mismatch, skipping FIXTURE_ROOT cleanup"
fi

echo "=== Cleanup complete ==="
