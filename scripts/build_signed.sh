#!/bin/bash
# Build and sign SwiftSweep with Helper
# This script builds the app and helper with proper code signing

set -e

# Configuration
TEAM_ID="6429YPLDYU"
APP_BUNDLE_ID="com.swiftsweep.app"
HELPER_BUNDLE_ID="com.swiftsweep.helper"
BUILD_DIR=".build/release"
APP_NAME="SwiftSweepApp"
HELPER_NAME="SwiftSweepHelper"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Building SwiftSweep ===${NC}"

# 1. Build in release mode
echo -e "${YELLOW}Building release...${NC}"
swift build -c release

# 2. Create app bundle structure
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
HELPER_PATH="$APP_BUNDLE/Contents/Library/LaunchDaemons/$HELPER_BUNDLE_ID"

echo -e "${YELLOW}Creating app bundle...${NC}"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Library/LaunchDaemons"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Helper
cp "$BUILD_DIR/$HELPER_NAME" "$HELPER_PATH"

# Create Info.plist for main app
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$APP_BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>SwiftSweep</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

# Copy launchd plist
cp Helper/com.swiftsweep.helper.plist "$APP_BUNDLE/Contents/Library/LaunchDaemons/"

# 3. Sign Helper first (must be signed before main app)
echo -e "${YELLOW}Signing Helper...${NC}"
codesign --force --options runtime \
    --sign "Developer ID Application: Your Name ($TEAM_ID)" \
    --identifier "$HELPER_BUNDLE_ID" \
    "$HELPER_PATH"

# 4. Sign main app
echo -e "${YELLOW}Signing main app...${NC}"
codesign --force --options runtime \
    --sign "Developer ID Application: Your Name ($TEAM_ID)" \
    --identifier "$APP_BUNDLE_ID" \
    --entitlements scripts/entitlements/SwiftSweep.entitlements \
    "$APP_BUNDLE"

# 5. Verify
echo -e "${YELLOW}Verifying signatures...${NC}"
codesign -vvv --deep --strict "$APP_BUNDLE"

echo -e "${GREEN}=== Build Complete ===${NC}"
echo -e "App bundle: $APP_BUNDLE"
echo -e "To run: open $APP_BUNDLE"
