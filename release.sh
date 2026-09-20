#!/bin/bash
# Full release pipeline: Developer ID signing, notarization and stapling of the app and the disk image.
# Final artifacts land in dist/. Requires notarization credentials stored once with
#   xcrun notarytool store-credentials <profile> --apple-id <apple-id> --team-id HU5S996C2K --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")"
export SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Techtag GmbH (HU5S996C2K)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ttntfs}"
# Sign and notarize outside iCloud Drive: its file provider re-adds Finder metadata to synced
# bundles, which breaks a strict signature. Only the finished dmg and zip are copied into dist/.
export OUT_DIR="$HOME/Library/Caches/airdrop2x-release"
rm -rf "$OUT_DIR"

./build-app.sh
APP="$OUT_DIR/AirDrop2X.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")

echo "== notarizing the app =="
ditto -c -k --keepParent "$APP" "$OUT_DIR/notarize-app.zip"
xcrun notarytool submit "$OUT_DIR/notarize-app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$OUT_DIR/notarize-app.zip"
xcrun stapler staple "$APP"

echo "== building and notarizing the disk image (from the stapled app) =="
SKIP_BUILD=1 ./make-dmg.sh
DMG="$OUT_DIR/AirDrop2X-$VERSION.dmg"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "== zip of the stapled app for the release page =="
ditto -c -k --keepParent "$APP" "$OUT_DIR/AirDrop2X-$VERSION.zip"

echo "== verification =="
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vv -t exec "$APP"
spctl -a -vv -t open --context context:primary-signature "$DMG"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"

mkdir -p dist
cp "$DMG" "$OUT_DIR/AirDrop2X-$VERSION.zip" dist/
cp "$DMG" dist/AirDrop2X.dmg   # unversioned copy: the website links to releases/latest/download/AirDrop2X.dmg
echo "release artifacts: dist/AirDrop2X-$VERSION.dmg  dist/AirDrop2X-$VERSION.zip"
