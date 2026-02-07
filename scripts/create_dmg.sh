#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/create_dmg.sh --app /path/MyApp.app --output /path/MyApp.dmg [options]

Required:
  --app PATH              Path to .app bundle
  --output PATH           Output DMG path

Optional:
  --volume-name NAME      Mounted volume name (default: app name)
  --sign-identity NAME    codesign identity for DMG signing
  -h, --help              Show this help
EOF
}

APP_PATH=""
OUTPUT_PATH=""
VOLUME_NAME=""
SIGNING_IDENTITY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="${2:-}"
      shift 2
      ;;
    --sign-identity)
      SIGNING_IDENTITY="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$OUTPUT_PATH" ]]; then
  echo "Both --app and --output are required." >&2
  usage
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
if [[ -z "$VOLUME_NAME" ]]; then
  VOLUME_NAME="$(basename "$APP_PATH" .app)"
fi

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

STAGING_DIR="$WORK_DIR/staging"
mkdir -p "$STAGING_DIR"
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$(dirname "$OUTPUT_PATH")"
rm -f "$OUTPUT_PATH"

/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_PATH"

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$OUTPUT_PATH"
fi

echo "DMG created: $OUTPUT_PATH"
