#!/usr/bin/env bash
# Builds build/KeycronBat.app (release). Signs with $SIGN_IDENTITY, else the
# first "Apple Development" identity in the keychain, else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product KeycronBat
BIN="$(swift build -c release --show-bin-path)/KeycronBat"

APP=build/KeycronBat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/KeycronBat"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# A stable identity keeps the Input Monitoring grant across rebuilds;
# ad-hoc signatures change every build, so macOS treats each one as a new app.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}' || true)}"
codesign --force --sign "${IDENTITY:--}" "$APP"

echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
