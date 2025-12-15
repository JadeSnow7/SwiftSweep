#!/bin/bash
# MAS Archive Verification Script
# Run this after creating an archive with Apple Distribution profile

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
APP_PATH="${1:-}"
EXPECTED_APP_GROUP="group.com.swiftsweep.mas"
REQUIRED_ENTITLEMENTS=(
    "com.apple.security.app-sandbox"
    "com.apple.security.application-groups"
)

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 <path-to-SwiftSweepMAS.app>"
    echo "Example: $0 ~/Desktop/SwiftSweepMAS.app"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: App not found at $APP_PATH${NC}"
    exit 1
fi

APPEX_PATH="$APP_PATH/Contents/PlugIns/FinderSyncExtension.appex"

echo "=========================================="
echo "MAS Archive Verification"
echo "=========================================="
echo ""

# Function to check entitlements
check_entitlements() {
    local binary_path="$1"
    local name="$2"
    
    echo -e "${YELLOW}Checking $name entitlements...${NC}"
    
    # Extract entitlements
    local entitlements=$(codesign -d --entitlements :- "$binary_path" 2>/dev/null)
    
    if [ -z "$entitlements" ]; then
        echo -e "${RED}  ✗ No entitlements found${NC}"
        return 1
    fi
    
    # Check sandbox
    if echo "$entitlements" | grep -q "com.apple.security.app-sandbox"; then
        echo -e "${GREEN}  ✓ App Sandbox enabled${NC}"
    else
        echo -e "${RED}  ✗ App Sandbox NOT enabled${NC}"
        return 1
    fi
    
    # Check App Group
    if echo "$entitlements" | grep -q "$EXPECTED_APP_GROUP"; then
        echo -e "${GREEN}  ✓ App Group present: $EXPECTED_APP_GROUP${NC}"
    else
        echo -e "${RED}  ✗ App Group missing${NC}"
        return 1
    fi
    
    # Check get-task-allow (should be false for distribution)
    if echo "$entitlements" | grep -q "com.apple.security.get-task-allow.*true"; then
        echo -e "${RED}  ✗ get-task-allow is TRUE (must be false for MAS)${NC}"
        return 1
    else
        echo -e "${GREEN}  ✓ get-task-allow is false or absent${NC}"
    fi
    
    # Check bookmarks (for host app)
    if [ "$name" == "Host App" ]; then
        if echo "$entitlements" | grep -q "com.apple.security.files.bookmarks.app-scope"; then
            echo -e "${GREEN}  ✓ Bookmarks app-scope enabled${NC}"
        else
            echo -e "${YELLOW}  ⚠ Bookmarks app-scope not found (may be needed)${NC}"
        fi
    fi
    
    # Check user-selected files
    if echo "$entitlements" | grep -q "com.apple.security.files.user-selected"; then
        echo -e "${GREEN}  ✓ User-selected files access enabled${NC}"
    fi
    
    echo ""
    return 0
}

# Check if FinderSync extension is embedded
check_extension_embedded() {
    echo -e "${YELLOW}Checking extension embedding...${NC}"
    
    if [ -d "$APPEX_PATH" ]; then
        echo -e "${GREEN}  ✓ FinderSyncExtension.appex embedded${NC}"
    else
        echo -e "${RED}  ✗ FinderSyncExtension.appex NOT embedded${NC}"
        return 1
    fi
    echo ""
}

# Check PrivacyInfo.xcprivacy
check_privacy_info() {
    echo -e "${YELLOW}Checking PrivacyInfo...${NC}"
    
    local privacy_path="$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
    if [ -f "$privacy_path" ]; then
        echo -e "${GREEN}  ✓ PrivacyInfo.xcprivacy present${NC}"
    else
        # Check alternate location
        privacy_path=$(find "$APP_PATH" -name "PrivacyInfo.xcprivacy" 2>/dev/null | head -1)
        if [ -n "$privacy_path" ]; then
            echo -e "${GREEN}  ✓ PrivacyInfo.xcprivacy found at: $privacy_path${NC}"
        else
            echo -e "${YELLOW}  ⚠ PrivacyInfo.xcprivacy not found${NC}"
        fi
    fi
    echo ""
}

# Check code signature
check_signature() {
    local binary_path="$1"
    local name="$2"
    
    echo -e "${YELLOW}Verifying $name signature...${NC}"
    
    if codesign --verify --deep --strict "$binary_path" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Signature valid${NC}"
    else
        echo -e "${RED}  ✗ Signature invalid${NC}"
        return 1
    fi
    echo ""
}

# Print full entitlements for review
print_entitlements() {
    local binary_path="$1"
    local name="$2"
    
    echo -e "${YELLOW}$name entitlements (full):${NC}"
    codesign -d --entitlements :- "$binary_path" 2>/dev/null | plutil -p - 2>/dev/null || echo "  (Unable to parse)"
    echo ""
}

# Main checks
ERRORS=0

check_extension_embedded || ((ERRORS++))
check_entitlements "$APP_PATH" "Host App" || ((ERRORS++))
check_entitlements "$APPEX_PATH" "FinderSync Extension" || ((ERRORS++))
check_signature "$APP_PATH" "Host App" || ((ERRORS++))
check_signature "$APPEX_PATH" "FinderSync Extension" || ((ERRORS++))
check_privacy_info

echo "=========================================="
echo "Detailed Entitlements"
echo "=========================================="
print_entitlements "$APP_PATH" "Host App"
print_entitlements "$APPEX_PATH" "FinderSync Extension"

echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All checks passed! Ready for MAS submission.${NC}"
else
    echo -e "${RED}$ERRORS check(s) failed. Fix issues before submitting.${NC}"
    exit 1
fi
