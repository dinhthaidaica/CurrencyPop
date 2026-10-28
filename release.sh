#!/bin/bash
# ./release.sh v1.0
#
# Builds, signs with your Developer ID, notarises with Apple, staples the
# ticket and publishes a GitHub release. The result opens on someone else's
# Mac with a normal double-click and no warning.
#
# One-time setup, both of which need your Apple credentials, so do them yourself:
#
#   1. Install a "Developer ID Application" certificate:
#        Xcode > Settings > Accounts > your Apple ID > Manage Certificates
#        > + > Developer ID Application
#      Check it landed:  security find-identity -v -p codesigning
#
#   2. Store notarisation credentials in the keychain:
#        xcrun notarytool store-credentials CurrencyPop \
#          --apple-id you@example.com --team-id ABCDE12345 \
#          --password <app-specific-password from appleid.apple.com>
#
# Override the defaults with DEVELOPER_ID and NOTARY_PROFILE if your
# certificate or profile is named differently.

set -euo pipefail
cd "$(dirname "$0")"

TAG="${1:?usage: ./release.sh v1.0}"
IDENTITY="${DEVELOPER_ID:-Developer ID Application}"
PROFILE="${NOTARY_PROFILE:-CurrencyPop}"
APP="CurrencyPop.app"
ZIP="CurrencyPop.zip"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "No Developer ID Application certificate in the keychain. See step 1 at the top of this script." >&2
  exit 1
fi

./build.sh test
./build.sh

# --options runtime is the hardened runtime; notarisation refuses a build without it.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

# Re-zip so the download carries the stapled ticket, which is what lets the
# app open on a Mac that has never seen it and happens to be offline.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"

gh release create "$TAG" "$ZIP" \
  --title "CurrencyPop $TAG" \
  --generate-notes

rm -f "$ZIP"
echo "released $TAG"
