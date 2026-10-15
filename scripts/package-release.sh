#!/usr/bin/env bash
# Builds a distributable build/KeycronBat-<version>.zip (+ .sha256).
# Universal, stripped, ad-hoc signed: no certificate identity or local paths ship.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
UNIVERSAL=1 STRIP=1 SIGN_IDENTITY="${SIGN_IDENTITY:--}" scripts/build-app.sh

ZIP="build/KeycronBat-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent build/KeycronBat.app "$ZIP"
(cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")

echo "Packaged $ZIP"
