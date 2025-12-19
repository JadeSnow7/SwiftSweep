#!/bin/bash

# Build Universal Binary for SwiftSweep
# Builds for both arm64 and x86_64, then combines with lipo

set -e

# Configuration
APP_NAME="SwiftSweep"
EXECUTABLE_NAME="SwiftSweepApp"
HELPER_NAME="SwiftSweepHelper"
BUNDLE_ID="com.swiftsweep.app"
HELPER_BUNDLE_ID="com.swiftsweep.helper"
VERSION="${VERSION:-1.2.1}"
OUTPUT_DIR="Output"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
INFO_PLIST="Resources/Info.plist"
ENTITLEMENTS="Entitlements.plist"

# Signing Identity
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Aodong Hu (6429YPLDYU)}"

# Temp build dirs
ARM64_BUILD=".build/arm64-apple-macosx/release"
X86_BUILD=".build/x86_64-apple-macosx/release"
UNIVERSAL_BUILD=".build/universal"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Building Universal Binary ===${NC}"

# 1. Build for ARM64
echo -e "${YELLOW}Building for arm64...${NC}"
swift build -c release --arch arm64 --product ${EXECUTABLE_NAME}
swift build -c release --arch arm64 --product ${HELPER_NAME}

# 2. Build for x86_64
echo -e "${YELLOW}Building for x86_64...${NC}"
swift build -c release --arch x86_64 --product ${EXECUTABLE_NAME}
swift build -c release --arch x86_64 --product ${HELPER_NAME}

# 3. Create universal binaries
echo -e "${YELLOW}Creating Universal Binaries with lipo...${NC}"
mkdir -p "${UNIVERSAL_BUILD}"

lipo -create \
    "${ARM64_BUILD}/${EXECUTABLE_NAME}" \
    "${X86_BUILD}/${EXECUTABLE_NAME}" \
    -output "${UNIVERSAL_BUILD}/${EXECUTABLE_NAME}"

lipo -create \
    "${ARM64_BUILD}/${HELPER_NAME}" \
    "${X86_BUILD}/${HELPER_NAME}" \
    -output "${UNIVERSAL_BUILD}/${HELPER_NAME}"

# Verify
echo -e "${YELLOW}Verifying architectures...${NC}"
lipo -info "${UNIVERSAL_BUILD}/${EXECUTABLE_NAME}"
lipo -info "${UNIVERSAL_BUILD}/${HELPER_NAME}"

# 4. Create App Bundle
echo -e "${YELLOW}Creating App Bundle...${NC}"
rm -rf "${OUTPUT_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${APP_BUNDLE}/Contents/Library/LaunchDaemons"

# Copy universal executable
cp "${UNIVERSAL_BUILD}/${EXECUTABLE_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy universal helper
cp "${UNIVERSAL_BUILD}/${HELPER_NAME}" "${APP_BUNDLE}/Contents/Library/LaunchDaemons/${HELPER_BUNDLE_ID}"
chmod +x "${APP_BUNDLE}/Contents/Library/LaunchDaemons/${HELPER_BUNDLE_ID}"

# Copy Helper plist
cp "Helper/com.swiftsweep.helper.plist" "${APP_BUNDLE}/Contents/Library/LaunchDaemons/"

# Copy Icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Create Info.plist
if [ -f "${INFO_PLIST}" ]; then
    sed -e "s/\$(PRODUCT_NAME)/${APP_NAME}/g" \
        -e "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" \
        -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
        -e "s/\$(MARKETING_VERSION)/${VERSION}/g" \
        -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
        "${INFO_PLIST}" > "${APP_BUNDLE}/Contents/Info.plist"
fi

# Copy SPM resource bundles (for localization)
echo -e "${YELLOW}Copying resource bundles...${NC}"
RESOURCE_BUNDLE="${ARM64_BUILD}/SwiftSweep_SwiftSweepUI.bundle"
if [ -d "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
    echo "Copied SwiftSweep_SwiftSweepUI.bundle"
fi

# 5. Code Signing
echo -e "${YELLOW}Signing Helper...${NC}"
codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" \
    --identifier "${HELPER_BUNDLE_ID}" \
    "${APP_BUNDLE}/Contents/Library/LaunchDaemons/${HELPER_BUNDLE_ID}"

echo -e "${YELLOW}Signing App Bundle...${NC}"
codesign --force --options runtime --timestamp --deep --sign "${SIGNING_IDENTITY}" \
    --entitlements "${ENTITLEMENTS}" "${APP_BUNDLE}"

# 6. Verify
echo -e "${YELLOW}Verifying signatures...${NC}"
codesign --verify --verbose "${APP_BUNDLE}"

# 7. Create DMG
echo -e "${YELLOW}Creating DMG...${NC}"
DMG_PATH="${OUTPUT_DIR}/${APP_NAME}.dmg"
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_BUNDLE}" -ov -format UDZO "${DMG_PATH}"

echo -e "${YELLOW}Signing DMG...${NC}"
codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"

echo -e "${YELLOW}Verifying DMG signature...${NC}"
codesign --verify --verbose=2 "${DMG_PATH}"

echo -e "${GREEN}=== Universal Build Complete ===${NC}"
echo "App Bundle: ${APP_BUNDLE}"
echo "DMG: ${DMG_PATH}"
lipo -info "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
