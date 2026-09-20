#!/bin/bash
# Builds a distributable disk image: dist/AirDrop2X-<version>.dmg containing AirDrop2X.app and an
# Applications shortcut, so installing is drag-and-drop. Runs build-app.sh first.
set -euo pipefail
cd "$(dirname "$0")"
./build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/AirDrop2X.app/Contents/Info.plist)
DMG="dist/AirDrop2X-$VERSION.dmg"
STAGE=$(mktemp -d)
cp -R dist/AirDrop2X.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "AirDrop2X $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --sign - "$DMG" >/dev/null 2>&1 || true
echo "built $DMG ($(du -h "$DMG" | cut -f1))"
