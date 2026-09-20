#!/bin/bash
# Builds dist/AirDrop2X.app (menu bar app) and dist/airdrop2x (command-line companion).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release 2>&1 | tail -1
BIN=$(swift build -c release --show-bin-path)
APP=dist/AirDrop2X.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AirDrop2xApp" "$APP/Contents/MacOS/AirDrop2X"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
[ -f Packaging/AppIcon.icns ] || (cd Packaging && swift make-icon.swift AppIcon.icns)
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/airdrop2x" dist/airdrop2x
codesign --force --sign - --identifier ch.techtag.airdrop2x "$APP"
echo "built $APP and dist/airdrop2x"
