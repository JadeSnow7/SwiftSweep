#!/bin/bash

# Configuration
APP_NAME="SwiftSweep"
EXECUTABLE_NAME="SwiftSweepApp"
BUNDLE_ID="com.swiftsweep.app"
VERSION="1.0.0"
BUILD_DIR=".build/release"
OUTPUT_DIR="Output"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
INFO_PLIST="Resources/Info.plist"
ENTITLEMENTS="Entitlements.plist"

# Signing Identity (Set this to your Developer ID Application certificate name)
# Example: "Developer ID Application: John Doe (TEAMID)"
SIGNING_IDENTITY="" 

# ANSI Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Starting Packaging Process for ${APP_NAME}...${NC}"

# 1. Build
echo "Building Release configuration..."
swift build -c release --product ${EXECUTABLE_NAME}
if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

# 2. Structure Creation
echo "Creating App Bundle structure..."
rm -rf "${OUTPUT_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 3. Copy Executable
echo "Copying executable..."
cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 4. Create Info.plist
echo "Configuring Info.plist..."
if [ -f "${INFO_PLIST}" ]; then
    sed -e "s/\$(PRODUCT_NAME)/${APP_NAME}/g" \
        -e "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" \
        -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
        -e "s/\$(MARKETING_VERSION)/${VERSION}/g" \
        "${INFO_PLIST}" > "${APP_BUNDLE}/Contents/Info.plist"
else
    echo -e "${YELLOW}Warning: Info.plist not found at ${INFO_PLIST}. Using simple custom one.${NC}"
    cat <<EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
fi

# 5. Code Signing
if [ -n "${SIGNING_IDENTITY}" ]; then
    echo "Signing with identity: ${SIGNING_IDENTITY}"
    codesign --force --options runtime --deep --sign "${SIGNING_IDENTITY}" --entitlements "${ENTITLEMENTS}" "${APP_BUNDLE}"
    
    echo "Verifying signature..."
    codesign --verify --verbose "${APP_BUNDLE}"
else
    echo -e "${YELLOW}Skipping Code Signing (No Identity provided).${NC}"
    echo "To sign, edit SIGNING_IDENTITY in this script."
    echo "Ad-hoc signing..."
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo -e "${GREEN}Packaging Complete!${NC}"
echo "App Bundle: ${APP_BUNDLE}"

# 6. Notarization Instructions
echo ""
echo -e "${YELLOW}--- Notarization Instructions ---${NC}"
echo "1. Zip the app: /usr/bin/ditto -c -k --keepParent \"${APP_BUNDLE}\" \"${OUTPUT_DIR}/${APP_NAME}.zip\""
echo "2. Submit: xcrun notarytool submit \"${OUTPUT_DIR}/${APP_NAME}.zip\" --keychain-profile \"YourProfileName\" --wait"
echo "3. Staple: xcrun stapler staple \"${APP_BUNDLE}\""
