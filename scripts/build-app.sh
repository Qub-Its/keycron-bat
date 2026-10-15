#!/usr/bin/env bash
# Builds build/KeycronBat.app (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product KeycronBat
BIN="$(swift build -c release --show-bin-path)/KeycronBat"

APP=build/KeycronBat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/KeycronBat"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
