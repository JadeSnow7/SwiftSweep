#!/bin/bash
set -euo pipefail

# E2E Fixture Setup Script
# Creates test fixtures for CleanupEngine E2E tests

FIXTURE_ROOT="/Library/Logs/SwiftSweepE2E"
TMP_FIXTURE="/tmp/SwiftSweepE2E"
SENTINEL="$FIXTURE_ROOT/.sentinel"
STANDARD_USER="${STANDARD_USER:-}"

echo "=== SwiftSweep E2E Fixture Setup ==="

# Non-root check
if [[ $(id -u) -eq 0 ]]; then
  echo "ERROR: Do not run this script as root directly"
  echo "Usage: ./setup_e2e_fixtures.sh"
  exit 1
fi

# Create fixture root
sudo mkdir -p "$FIXTURE_ROOT"
sudo touch "$SENTINEL"
sudo mkdir -p "$TMP_FIXTURE"

# 1. System file (root-owned, requires Helper)
echo "Creating system file fixtures..."
sudo touch "$FIXTURE_ROOT/system.log"
sudo chown root:wheel "$FIXTURE_ROOT/system.log"
sudo chmod 600 "$FIXTURE_ROOT/system.log"

# 2. Immutable file (chflags uchg)
echo "Creating immutable file fixture..."
sudo touch "$FIXTURE_ROOT/immutable.log"
sudo chflags uchg "$FIXTURE_ROOT/immutable.log"

# 3. Symlink escape fixture
echo "Creating symlink escape fixture..."
sudo touch "$TMP_FIXTURE/escape_target.txt"
sudo ln -sf "$TMP_FIXTURE" "$FIXTURE_ROOT/escape_link"

# 4. Standard user attack fixture (if user specified)
if [[ -n "$STANDARD_USER" ]]; then
  echo "Creating standard user attack fixture..."
  sudo mkdir -p "$FIXTURE_ROOT/writable"
  sudo chmod 777 "$FIXTURE_ROOT/writable"
  sudo -u "$STANDARD_USER" ln -sf /etc/passwd "$FIXTURE_ROOT/writable/attack_link"
fi

# 5. Denied path fixture (outside allowlist)
echo "Creating denied path fixture..."
sudo touch "$TMP_FIXTURE/denied.dat"
sudo chown root:wheel "$TMP_FIXTURE/denied.dat"

# 6. Empty directory
echo "Creating empty directory fixture..."
sudo mkdir -p "$FIXTURE_ROOT/empty_dir"

# 7. Non-empty directory
echo "Creating non-empty directory fixture..."
sudo mkdir -p "$FIXTURE_ROOT/nonempty_dir"
sudo touch "$FIXTURE_ROOT/nonempty_dir/child.txt"

echo "=== Fixture setup complete ==="
echo "FIXTURE_ROOT: $FIXTURE_ROOT"
echo "TMP_FIXTURE: $TMP_FIXTURE"
