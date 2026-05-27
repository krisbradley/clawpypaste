#!/usr/bin/env bash
# Builds, signs, notarizes, staples, and zips clawpypaste.app for release.
# After this finishes, clawpypaste.zip is ready to upload to a GitHub Release.
set -euo pipefail
cd "$(dirname "$0")"

APP_BUNDLE="clawpypaste.app"
ZIP_NAME="clawpypaste.zip"
NOTARY_PROFILE="${CLAWPYPASTE_NOTARY_PROFILE:-clawpypaste}"

# Always rebuild — easier to reason about than partial state.
./build-app.sh

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
echo "Verifying Gatekeeper acceptance..."
spctl --assess --verbose=2 --type execute "${APP_BUNDLE}" 2>&1 | sed 's/^/   /' || true

echo ""
echo "✓ ${ZIP_NAME} is signed, notarized, and stapled."
ls -lh "${ZIP_NAME}"
shasum -a 256 "${ZIP_NAME}"
echo ""
echo "Next:  gh release create vX.Y.Z ${ZIP_NAME}"
