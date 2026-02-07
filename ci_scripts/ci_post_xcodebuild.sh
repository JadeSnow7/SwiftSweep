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

resolve_release_repo() {
  if [[ -n "${SWIFTSWEEP_CI_RELEASE_REPO:-}" ]]; then
    printf '%s\n' "${SWIFTSWEEP_CI_RELEASE_REPO}"
    return 0
  fi

  local origin_url
  origin_url="$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null || true)"
  if [[ -z "$origin_url" ]]; then
    return 1
  fi

  printf '%s\n' "$origin_url" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##'
}

resolve_release_tag() {
  if [[ -n "${SWIFTSWEEP_CI_RELEASE_TAG:-}" ]]; then
    printf '%s\n' "${SWIFTSWEEP_CI_RELEASE_TAG#refs/tags/}"
    return 0
  fi

  if [[ -n "${CI_TAG:-}" ]]; then
    printf '%s\n' "${CI_TAG#refs/tags/}"
    return 0
  fi

  if [[ -n "${CI_GIT_REF:-}" && "${CI_GIT_REF}" == refs/tags/* ]]; then
    printf '%s\n' "${CI_GIT_REF#refs/tags/}"
    return 0
  fi

  git -C "$REPO_ROOT" tag --points-at HEAD | head -n 1
}

publish_github_release() {
  if [[ "${SWIFTSWEEP_CI_UPLOAD_RELEASE:-0}" != "1" ]]; then
    echo "SwiftSweep: GitHub Release upload disabled (set SWIFTSWEEP_CI_UPLOAD_RELEASE=1 to enable)."
    return 0
  fi

  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [[ -z "$token" ]]; then
    echo "SwiftSweep: release upload requested but GH_TOKEN/GITHUB_TOKEN is missing."
    exit 1
  fi
  export GH_TOKEN="$token"

  local repo
  repo="$(resolve_release_repo || true)"
  if [[ -z "$repo" ]]; then
    echo "SwiftSweep: unable to resolve GitHub repo. Set SWIFTSWEEP_CI_RELEASE_REPO=owner/repo."
    exit 1
  fi

  local tag
  tag="$(resolve_release_tag || true)"
  if [[ -z "$tag" ]]; then
    echo "SwiftSweep: unable to resolve release tag. Set SWIFTSWEEP_CI_RELEASE_TAG (e.g. v1.7.2)."
    exit 1
  fi

  if ! command -v gh >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      echo "SwiftSweep: gh CLI not found, installing via Homebrew..."
      HOMEBREW_NO_AUTO_UPDATE=1 brew install gh
    else
      echo "SwiftSweep: gh CLI is required for release upload but Homebrew is unavailable."
      exit 1
    fi
  fi

  echo "SwiftSweep: publishing assets to GitHub release ${repo}@${tag}..."
  if ! gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    gh release create "$tag" --repo "$repo" --title "$tag" --generate-notes
  fi

  gh release upload "$tag" "$FINAL_DMG" "$FINAL_SHA" --repo "$repo" --clobber
  echo "SwiftSweep: release upload complete: https://github.com/${repo}/releases/tag/${tag}"
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
DMG_SCRIPT="${REPO_ROOT}/scripts/create_dmg.sh"
chmod +x "$DMG_SCRIPT"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | sed -n 's/.*\"\\(Developer ID Application:.*\\)\".*/\\1/p' | head -n 1 || true)"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "SwiftSweep: creating DMG with identity: $SIGNING_IDENTITY"
  "$DMG_SCRIPT" \
    --app "$APP_WORK" \
    --output "$DMG_PATH" \
    --volume-name "$OUTPUT_NAME" \
    --sign-identity "$SIGNING_IDENTITY"
else
  echo "SwiftSweep: creating DMG without signing (no Developer ID identity found)."
  "$DMG_SCRIPT" \
    --app "$APP_WORK" \
    --output "$DMG_PATH" \
    --volume-name "$OUTPUT_NAME"
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

publish_github_release
