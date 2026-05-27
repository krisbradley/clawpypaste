#!/usr/bin/env bash
# Bundles the Swift Package binary into a proper macOS .app so you can drop
# it in /Applications and register it as a Login Item.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="clawpypaste"
APP_BUNDLE="${APP_NAME}.app"
BUNDLE_ID="com.kristopherbradley.${APP_NAME}"
VERSION="0.1.0"

echo "Building release binary..."
swift build -c release

echo "Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp ".build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
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
    <key>NSHumanReadableCopyright</key>
    <string></string>
</dict>
</plist>
EOF

# Ad-hoc sign so macOS doesn't quarantine-block it.
codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true

echo ""
echo "Built ${APP_BUNDLE}"
echo ""
echo "Install:"
echo "  mv ${APP_BUNDLE} /Applications/"
echo "  open /Applications/${APP_BUNDLE}"
echo ""
echo "After launch, right-click the menu bar icon and toggle 'Launch at login'."
