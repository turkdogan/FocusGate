#!/bin/bash
set -euo pipefail

# FocusGate release pipeline — mirrors prio/scripts/release.sh, adapted for
# an Xcode project that ships a Network Extension system extension.
#
# Usage: ./scripts/release.sh <version> <build_number>
# Example: ./scripts/release.sh 1.0.0 12
#
# PREREQUISITES (one-time):
#  1. Apple must grant the team the Developer ID Network Extension
#     entitlement (request: developer.apple.com/contact/request/network-extension/).
#     Without it, notarization succeeds but the extension will not activate
#     on other Macs.
#  2. Developer ID provisioning profiles for dev.turkdogan.FocusGate and
#     dev.turkdogan.FocusGate.FocusGateExtension installed in Xcode.
#  3. The Developer ID build must use the -systemextension entitlement
#     variants (content-filter-provider-systemextension, dns-proxy-systemextension)
#     — see FocusGateExtension-DeveloperID.entitlements.
#  4. notarytool keychain profile:
#     xcrun notarytool store-credentials focusgate-notary \
#       --apple-id ttasdelen@gmail.com --team-id 9B6S2Y8856

VERSION="${1:?Usage: release.sh <version> <build_number>}"
BUILD_NUM="${2:?Usage: release.sh <version> <build_number>}"

ARCHIVE="dist/FocusGate.xcarchive"
EXPORT_DIR="dist/export"
APP_DIR="$EXPORT_DIR/FocusGate.app"
ZIP="dist/FocusGate-${VERSION}.zip"
KEYCHAIN_PROFILE="focusgate-notary"

mkdir -p dist

echo "=== FocusGate Release v${VERSION} (build ${BUILD_NUM}) ==="

echo "[1/6] Archiving (Release, Developer ID)..."
xcodebuild -project FocusGate.xcodeproj -scheme FocusGate -configuration Release \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUM" \
    archive

echo "[2/6] Exporting with Developer ID signing..."
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$EXPORT_DIR"

echo "[3/6] Verifying signature and gatekeeper assessment..."
codesign --verify --deep --strict=all "$APP_DIR"
codesign -d --entitlements - --xml \
    "$APP_DIR/Contents/Library/SystemExtensions/dev.turkdogan.FocusGate.FocusGateExtension.systemextension" \
    | grep -q "systemextension" \
    || { echo "ERROR: extension lacks -systemextension entitlements (Developer ID profile missing?)"; exit 1; }

echo "[4/6] Notarizing..."
rm -f "$ZIP"
ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "[5/6] Stapling and creating final zip..."
xcrun stapler staple "$APP_DIR"
xattr -cr "$APP_DIR"   # provenance xattr triggers "unsealed contents" on Sonoma
rm -f "$ZIP"
ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP"
spctl --assess --type execute "$APP_DIR" && echo "Gatekeeper OK"

echo "[6/6] Publishing GitHub release..."
gh release create "v${VERSION}" "$ZIP" \
    --title "FocusGate ${VERSION}" \
    --generate-notes

echo "=== Done! ==="
echo "Distributable: $ZIP"
