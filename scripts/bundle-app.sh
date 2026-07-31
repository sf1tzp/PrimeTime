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
# The scriptable CLI (#80) rides in the bundle under its user-facing name —
# the SwiftPM product is primetime-cli only to dodge the case-insensitive
# .build collision with the app binary. Users get it on PATH via the cask's
# binary stanza (or a manual symlink to Contents/Helpers/primetime).
mkdir -p "$APP/Contents/Helpers"
cp "$ROOT/.build/release/primetime-cli" "$APP/Contents/Helpers/primetime"
# Sparkle rides along for auto-update (#46) — SwiftPM drops the framework next
# to the binary; the bundled binary reaches this copy via the
# @executable_path/../Frameworks rpath set in Package.swift.
mkdir -p "$APP/Contents/Frameworks"
ditto "$ROOT/.build/release/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# The SwiftPM resource bundle (brand font + masthead icon). Brand.resources
# looks here — swift build's Bundle.module accessor does NOT check
# Contents/Resources, only the .app root and the builder's absolute .build path.
ditto "$ROOT/.build/release/PrimeTime_PrimeTime.bundle" \
      "$APP/Contents/Resources/PrimeTime_PrimeTime.bundle"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" \
    "$ROOT/scripts/Info.plist.in" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "Built $APP ($VERSION, build $BUILD)"
