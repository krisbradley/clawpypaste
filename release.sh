#!/usr/bin/env bash
# Builds, signs, notarizes, staples, and zips clawpypaste.app for release.
# After this finishes, clawpypaste.zip is ready to upload to a GitHub Release.
set -euo pipefail
cd "$(dirname "$0")"

APP_BUNDLE="clawpypaste.app"
ZIP_NAME="clawpypaste.zip"
DMG_NAME="clawpypaste.dmg"
NOTARY_PROFILE="${CLAWPYPASTE_NOTARY_PROFILE:-clawpypaste}"
SIGN_IDENTITY="${CLAWPYPASTE_SIGN_IDENTITY:-Developer ID Application: Kris Bradley (JEE5UP73GN)}"

# Always rebuild — easier to reason about than partial state.
./build-app.sh

# Stale-build guard: refuse to ship a binary that predates the sources or
# reports a different version than build-app.sh set. (A toolchain change once
# moved SwiftPM's output dir and we silently packaged an old binary.)
echo ""
echo "Verifying the packaged binary is fresh..."
BIN="${APP_BUNDLE}/Contents/MacOS/clawpypaste"
EXPECTED_VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' build-app.sh)"
BUNDLE_VERSION="$(defaults read "$PWD/${APP_BUNDLE}/Contents/Info.plist" CFBundleShortVersionString)"
if [ "${BUNDLE_VERSION}" != "${EXPECTED_VERSION}" ]; then
    echo "✗ bundle version ${BUNDLE_VERSION} != build-app.sh VERSION ${EXPECTED_VERSION}" >&2
    exit 1
fi
if ! lipo -info "${BIN}" | grep -q "x86_64" || ! lipo -info "${BIN}" | grep -q "arm64"; then
    echo "✗ binary is not universal: $(lipo -info "${BIN}")" >&2
    exit 1
fi
echo "   ✓ v${BUNDLE_VERSION}, universal (source freshness checked in build-app.sh)"

echo ""
echo "Zipping ${APP_BUNDLE}..."
rm -f "${ZIP_NAME}"
# ditto preserves extended attributes and code signatures correctly,
# unlike `zip` which can corrupt the .app bundle.
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_NAME}"

echo ""
echo "Submitting to Apple notarization service..."
echo "(typically 1-5 minutes; --wait blocks until done)"
xcrun notarytool submit "${ZIP_NAME}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

echo ""
echo "Stapling notarization ticket to app bundle..."
xcrun stapler staple "${APP_BUNDLE}"

echo ""
echo "Re-zipping stapled app..."
rm -f "${ZIP_NAME}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_NAME}"

echo ""
echo "Building ${DMG_NAME} (drag-to-Applications disk image)..."
STAGE="$(mktemp -d)"
ditto "${APP_BUNDLE}" "${STAGE}/${APP_BUNDLE}"
ln -s /Applications "${STAGE}/Applications"
rm -f "${DMG_NAME}"
hdiutil create -volname clawpypaste -srcfolder "${STAGE}" -ov -format UDZO "${DMG_NAME}" >/dev/null
rm -rf "${STAGE}"
codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_NAME}"
echo "Notarizing ${DMG_NAME}..."
xcrun notarytool submit "${DMG_NAME}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG_NAME}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_NAME}" 2>&1 | sed 's/^/   /' || true

echo ""
echo "Verifying Gatekeeper acceptance..."
spctl --assess --verbose=2 --type execute "${APP_BUNDLE}" 2>&1 | sed 's/^/   /' || true

echo ""
echo "✓ ${ZIP_NAME} and ${DMG_NAME} are signed, notarized, and stapled."
ls -lh "${ZIP_NAME}" "${DMG_NAME}"
shasum -a 256 "${ZIP_NAME}"
echo ""
echo "Next:  gh release create vX.Y.Z ${ZIP_NAME} ${DMG_NAME}   (cask sha256 = the zip's)"
