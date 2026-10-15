#!/usr/bin/env bash
# Builds build/KeycronBat.app (release). Signs with $SIGN_IDENTITY, else the
# first "Apple Development" identity in the keychain, else ad-hoc.
# UNIVERSAL=1 builds for both arm64 and x86_64; STRIP=1 drops debug symbols
# (and the local build paths they embed).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_FLAGS=(-c release)
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_FLAGS[@]}" --product KeycronBat
BIN="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/KeycronBat"

APP=build/KeycronBat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/KeycronBat"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ "${STRIP:-0}" == 1 ]]; then
    strip -S -x "$APP/Contents/MacOS/KeycronBat"
fi

# A stable identity keeps the Input Monitoring grant across rebuilds;
# ad-hoc signatures change every build, so macOS treats each one as a new app.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}' || true)}"
codesign --force --sign "${IDENTITY:--}" "$APP"

echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
