#!/bin/bash
# Builds a distributable disk image AirDrop2X-<version>.dmg in OUT_DIR (default dist), containing
# AirDrop2X.app and an Applications shortcut for drag-and-drop install. Runs build-app.sh first unless SKIP_BUILD=1.
set -euo pipefail
cd "$(dirname "$0")"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
OUT="${OUT_DIR:-dist}"
[ "${SKIP_BUILD:-0}" = "1" ] || ./build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OUT/AirDrop2X.app/Contents/Info.plist")
DMG="$OUT/AirDrop2X-$VERSION.dmg"
STAGE=$(mktemp -d)
cp -R "$OUT/AirDrop2X.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "AirDrop2X $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$DMG" >/dev/null 2>&1 || true
else
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
echo "built $DMG ($(du -h "$DMG" | cut -f1))"
