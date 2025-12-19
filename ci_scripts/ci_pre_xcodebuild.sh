#!/bin/bash
set -euo pipefail

if [[ -z "${MACOS_CERTIFICATE:-}" ]]; then
  echo "SwiftSweep: no MACOS_CERTIFICATE provided; skipping code signing cert import."
  exit 0
fi

if [[ -z "${MACOS_CERTIFICATE_PWD:-}" ]]; then
  echo "SwiftSweep: MACOS_CERTIFICATE_PWD is required when MACOS_CERTIFICATE is set."
  exit 1
fi

KEYCHAIN_PATH="${CI_KEYCHAIN_PATH:-}"
KEYCHAIN_PASSWORD="${CI_KEYCHAIN_PASSWORD:-${KEYCHAIN_PASSWORD:-}}"

if [[ -n "$KEYCHAIN_PATH" && -f "$KEYCHAIN_PATH" ]]; then
  if [[ -z "$KEYCHAIN_PASSWORD" ]]; then
    echo "SwiftSweep: CI_KEYCHAIN_PASSWORD is required when CI_KEYCHAIN_PATH is set."
    exit 1
  fi
else
  KEYCHAIN_PATH="${TMPDIR:-/tmp}/swiftsweep-ci.keychain"
  if [[ -z "$KEYCHAIN_PASSWORD" ]]; then
    KEYCHAIN_PASSWORD="$(uuidgen)"
  fi

  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
  security list-keychains -d user -s "$KEYCHAIN_PATH"
  security default-keychain -s "$KEYCHAIN_PATH"
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

CERT_PATH="$(mktemp -t swiftsweep_cert.XXXXXX.p12)"
cleanup() { rm -f "$CERT_PATH"; }
trap cleanup EXIT

printf '%s' "$MACOS_CERTIFICATE" | base64 --decode > "$CERT_PATH"

security import "$CERT_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$MACOS_CERTIFICATE_PWD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/productbuild

security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

echo "SwiftSweep: available code signing identities:"
security find-identity -p codesigning -v "$KEYCHAIN_PATH" || security find-identity -p codesigning -v
