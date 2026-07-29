#!/usr/bin/env bash
# Assemble dist/PrimeTime.app from the SwiftPM release build.
#
# The bundle ships under the PrimeTime identity (#44); target and binary
# are also named PrimeTime since the rename, so the copy is 1:1.
#
# Env:
#   VERSION      marketing version (default: git describe, 0.0.0 before any tag)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PrimeTime"
APP="$ROOT/dist/$APP_NAME.app"

VERSION="${VERSION:-$(git -C "$ROOT" describe --tags 2>/dev/null || echo 0.0.0)}"
VERSION="${VERSION#v}"
BUILD="$(git -C "$ROOT" rev-list --count HEAD)"

# arm64-only: Intel support ends with macOS 26, and there's no Rosetta in
# that direction — a universal build would only serve machines on their way out.
swift build --package-path "$ROOT" -c release
BIN="$ROOT/.build/release/PrimeTime"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" \
    "$ROOT/scripts/Info.plist.in" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "Built $APP ($VERSION, build $BUILD)"
