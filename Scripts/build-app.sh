#!/bin/bash
# Builds build/Dustpan.app and build/dustpan (the command-line tool).
#
#   Scripts/build-app.sh               # this Mac's architecture, ad-hoc signed
#   Scripts/build-app.sh --universal   # Apple silicon + Intel
#
# Environment:
#   SIGN_IDENTITY  codesign identity, e.g. "Developer ID Application: Your Name (TEAMID)". Default: ad-hoc.
#   BUNDLE_ID      bundle identifier. Default: io.github.arypak.Dustpan
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/DustpanCore/Dustpan.swift)
BUNDLE_ID="${BUNDLE_ID:-io.github.arypak.Dustpan}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
# Notarization needs a secure timestamp; ad-hoc signatures can't have one.
TIMESTAMP=--timestamp=none
if [[ "$SIGN_IDENTITY" != "-" ]]; then TIMESTAMP=--timestamp; fi

ARCHS=(--arch "$(uname -m)")
if [[ "${1:-}" == "--universal" ]]; then
  ARCHS=(--arch arm64 --arch x86_64)
fi

swift build -c release "${ARCHS[@]}" --product DustpanApp
swift build -c release "${ARCHS[@]}" --product dustpan
BIN=$(swift build -c release "${ARCHS[@]}" --show-bin-path)

APP=build/Dustpan.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/DustpanApp" "$APP/Contents/MacOS/Dustpan"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" -e "s/__BUNDLE_ID__/$BUNDLE_ID/" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$BIN/dustpan" build/dustpan

codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_IDENTITY" build/dustpan
codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP and build/dustpan, version $VERSION ($BUILD_NUMBER)"
