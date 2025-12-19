#!/bin/bash
set -euo pipefail

if [[ "${SWIFTSWEEP_CI_EXPORT_DMG:-0}" != "1" ]]; then
  echo "SwiftSweep: DMG export disabled (set SWIFTSWEEP_CI_EXPORT_DMG=1 to enable)."
  exit 0
fi

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(pwd)}"
APP_NAME="${SWIFTSWEEP_APP_NAME:-SwiftSweep}"
OUTPUT_NAME="${SWIFTSWEEP_OUTPUT_NAME:-}"

ARTIFACTS_DIR="${CI_ARTIFACTS_PATH:-$REPO_ROOT/Output}"
mkdir -p "$ARTIFACTS_DIR"

if [[ -z "${CI_ARCHIVE_PATH:-}" || ! -d "${CI_ARCHIVE_PATH}" ]]; then
  if [[ "${SWIFTSWEEP_CI_SPM_BUILD:-0}" != "1" ]]; then
    echo "SwiftSweep: CI_ARCHIVE_PATH is not set or missing."
    echo "Use an Archive action, or set SWIFTSWEEP_CI_SPM_BUILD=1 to build via SwiftPM packaging script."
    echo "CI_ARCHIVE_PATH=${CI_ARCHIVE_PATH:-<unset>}"
    exit 1
  fi
fi

APP_IN_ARCHIVE=""
if [[ -n "${CI_ARCHIVE_PATH:-}" && -d "${CI_ARCHIVE_PATH}" ]]; then
  APP_IN_ARCHIVE="${CI_ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
  if [[ ! -d "$APP_IN_ARCHIVE" ]]; then
    FOUND_APP="$(find "${CI_ARCHIVE_PATH}/Products/Applications" -maxdepth 1 -type d -name "*.app" -print -quit 2>/dev/null || true)"
    if [[ -n "$FOUND_APP" ]]; then
      APP_IN_ARCHIVE="$FOUND_APP"
      APP_NAME="$(basename "$APP_IN_ARCHIVE" .app)"
      echo "SwiftSweep: APP_NAME not found in archive; using detected app: $APP_NAME"
    else
      echo "SwiftSweep: no .app found in archive at: ${CI_ARCHIVE_PATH}/Products/Applications"
      exit 1
    fi
  fi
else
  echo "SwiftSweep: building via SwiftPM packaging script..."
  chmod +x "${REPO_ROOT}/scripts/build_universal.sh"
  (cd "$REPO_ROOT" && ./scripts/build_universal.sh)
  APP_IN_ARCHIVE="${REPO_ROOT}/Output/${APP_NAME}.app"
  if [[ ! -d "$APP_IN_ARCHIVE" ]]; then
    echo "SwiftSweep: expected app bundle not found after SwiftPM build: $APP_IN_ARCHIVE"
    exit 1
  fi
fi

if [[ -z "$OUTPUT_NAME" ]]; then
  OUTPUT_NAME="$APP_NAME"
fi

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

APP_WORK="${WORK_DIR}/${APP_NAME}.app"
/usr/bin/ditto "$APP_IN_ARCHIVE" "$APP_WORK"

if [[ "$OUTPUT_NAME" != "$APP_NAME" ]]; then
  mv "$APP_WORK" "${WORK_DIR}/${OUTPUT_NAME}.app"
  APP_WORK="${WORK_DIR}/${OUTPUT_NAME}.app"
fi

echo "SwiftSweep: verifying app signature (best-effort)..."
codesign --verify --deep --strict --verbose=2 "$APP_WORK" || true

submit_notarization() {
  local file_path="$1"

  if [[ "${SWIFTSWEEP_CI_NOTARIZE:-0}" != "1" ]]; then
    echo "SwiftSweep: notarization disabled (set SWIFTSWEEP_CI_NOTARIZE=1 to enable)."
    return 0
  fi

  if [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" && -n "${NOTARY_PRIVATE_KEY_BASE64:-}" ]]; then
    local key_path="${WORK_DIR}/AuthKey.p8"
    printf '%s' "$NOTARY_PRIVATE_KEY_BASE64" | base64 --decode > "$key_path"

    xcrun notarytool submit "$file_path" \
      --key "$key_path" \
      --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" \
      --wait
    return 0
  fi

  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$file_path" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" \
      --wait
    return 0
  fi

  echo "SwiftSweep: missing notarization credentials."
  echo "Set either:"
  echo "  - NOTARY_KEY_ID + NOTARY_ISSUER_ID + NOTARY_PRIVATE_KEY_BASE64 (App Store Connect API key), or"
  echo "  - APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD (app-specific password)."
  exit 1
}

echo "SwiftSweep: notarize+staple app..."
APP_ZIP="${WORK_DIR}/${OUTPUT_NAME}.zip"
/usr/bin/ditto -c -k --keepParent "$APP_WORK" "$APP_ZIP"
submit_notarization "$APP_ZIP"
if [[ "${SWIFTSWEEP_CI_NOTARIZE:-0}" == "1" ]]; then
  xcrun stapler staple "$APP_WORK"
fi

echo "SwiftSweep: create DMG..."
DMG_PATH="${WORK_DIR}/${OUTPUT_NAME}.dmg"
/usr/bin/hdiutil create -volname "$OUTPUT_NAME" -srcfolder "$APP_WORK" -ov -format UDZO "$DMG_PATH"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | sed -n 's/.*\"\\(Developer ID Application:.*\\)\".*/\\1/p' | head -n 1 || true)"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "SwiftSweep: signing DMG with identity: $SIGNING_IDENTITY"
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
else
  echo "SwiftSweep: SIGNING_IDENTITY not set and no Developer ID identity found; skipping DMG signing."
fi

echo "SwiftSweep: notarize+staple DMG..."
submit_notarization "$DMG_PATH"
if [[ "${SWIFTSWEEP_CI_NOTARIZE:-0}" == "1" ]]; then
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate -v "$DMG_PATH" || true
fi

echo "SwiftSweep: verify (best-effort)..."
codesign --verify --verbose=2 "$DMG_PATH" || true
codesign --verify --deep --strict --verbose=2 "$APP_WORK" || true
spctl -a -vv "$APP_WORK" || true
spctl -a -vv --type open --context context:primary-signature "$DMG_PATH" || true

echo "SwiftSweep: write artifacts..."
FINAL_DMG="${ARTIFACTS_DIR}/${OUTPUT_NAME}.dmg"
FINAL_SHA="${ARTIFACTS_DIR}/${OUTPUT_NAME}.dmg.sha256"
cp -f "$DMG_PATH" "$FINAL_DMG"
shasum -a 256 "$FINAL_DMG" | awk '{print $1}' > "$FINAL_SHA"

echo "SwiftSweep: done."
echo "Artifacts:"
echo "  - $FINAL_DMG"
echo "  - $FINAL_SHA"
