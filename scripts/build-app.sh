#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64) GoodScroll.app into ./build.
# Usage: scripts/build-app.sh [version]        e.g. scripts/build-app.sh 1.0.0
# Env:   SIGN_IDENTITY  codesign identity (default "-" = ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

APP="build/GoodScroll.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --product GoodScroll
done
lipo -create \
  .build/arm64-apple-macosx/release/GoodScroll \
  .build/x86_64-apple-macosx/release/GoodScroll \
  -output "$APP/Contents/MacOS/GoodScroll"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"

(cd build && ditto -c -k --keepParent GoodScroll.app "GoodScroll-$VERSION.zip")
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/GoodScroll"))"
