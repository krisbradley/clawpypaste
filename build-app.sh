#!/usr/bin/env bash
# Bundles the Swift Package binary into a macOS .app and codesigns it.
#
# Without CLAWPYPASTE_SIGN_IDENTITY set, defaults to the Developer ID
# Application identity for this project; override to skip or change.
# Pass --adhoc to do an ad-hoc local-only signature (no notarization possible).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="clawpypaste"
APP_BUNDLE="${APP_NAME}.app"
BUNDLE_ID="com.kristopherbradley.${APP_NAME}"
VERSION="0.2.12"
SIGN_IDENTITY="${CLAWPYPASTE_SIGN_IDENTITY:-Developer ID Application: Kris Bradley (JEE5UP73GN)}"

MODE="developer-id"
if [ "${1:-}" = "--adhoc" ]; then
    MODE="adhoc"
fi

echo "Building release binary..."
swift build -c release

echo "Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp ".build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Generate AppIcon.icns from the 🦀 emoji at all required sizes.
echo "Generating app icon..."
ICONSET=".build/AppIcon.iconset"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"
swift tools/gen-icon.swift "${ICONSET}" 2>&1 | sed 's/^/   /'
iconutil -c icns "${ICONSET}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>clawpypaste needs to control your terminal to paste dropped files into your Claude Code prompt.</string>
    <key>NSHumanReadableCopyright</key>
    <string></string>
</dict>
</plist>
EOF

# Empty entitlements file is fine — non-sandboxed app with no special needs.
ENTITLEMENTS="$(mktemp -t clawpypaste-entitlements).plist"
cat > "${ENTITLEMENTS}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF

if [ "${MODE}" = "adhoc" ]; then
    echo "Signing ad-hoc (no notarization possible)..."
    codesign --force --deep --sign - "${APP_BUNDLE}"
else
    echo "Signing with: ${SIGN_IDENTITY}"
    codesign --force --options runtime --timestamp \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${SIGN_IDENTITY}" \
        "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
    codesign --force --options runtime --timestamp \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${SIGN_IDENTITY}" \
        "${APP_BUNDLE}"
fi
rm -f "${ENTITLEMENTS}"

echo ""
echo "✓ Built ${APP_BUNDLE} (${MODE})"
codesign -dv --verbose=2 "${APP_BUNDLE}" 2>&1 | grep -E 'Identifier|Authority|TeamIdentifier|Sealed' | sed 's/^/   /'
echo ""
echo "  Install locally:  make install"
echo "  Notarize + ship:  ./release.sh"
