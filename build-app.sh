#!/bin/bash
# Builds AirDrop2X.app (menu bar app) and airdrop2x (command-line companion) into OUT_DIR (default dist).
# SIGN_IDENTITY selects the code-signing identity; default is ad-hoc ("-"). release.sh sets Developer ID.
set -euo pipefail
cd "$(dirname "$0")"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
OUT="${OUT_DIR:-dist}"   # release.sh points this outside iCloud Drive, which re-adds Finder metadata to bundles
mkdir -p "$OUT"
swift build -c release 2>&1 | tail -1
BIN=$(swift build -c release --show-bin-path)
APP="$OUT/AirDrop2X.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AirDrop2xApp" "$APP/Contents/MacOS/AirDrop2X"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
[ -f Packaging/AppIcon.icns ] || (cd Packaging && swift make-icon.swift AppIcon.icns)
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/airdrop2x" "$OUT/airdrop2x"
xattr -cr "$APP" "$OUT/airdrop2x"   # Finder metadata would invalidate a strict signature
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - --identifier ch.techtag.airdrop2x "$APP"
else
    # Developer ID: hardened runtime and a secure timestamp are required for notarization.
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --identifier ch.techtag.airdrop2x "$APP"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$OUT/airdrop2x"
fi
echo "built $APP and $OUT/airdrop2x (signed: $SIGN_IDENTITY)"
