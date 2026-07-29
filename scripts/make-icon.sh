#!/usr/bin/env bash
# Render Resources/AppIcon.svg into Resources/AppIcon.icns using Quick Look +
# iconutil — no third-party rasterizer required. The .icns is checked in so
# CI never runs this; re-run it after editing the SVG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/Resources/AppIcon.svg"
WORK="$(mktemp -d)"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"

render() { # px, iconset filename
    qlmanage -t -s "$1" -o "$WORK" "$SVG" >/dev/null
    mv "$WORK/AppIcon.svg.png" "$SET/$2"
}

for s in 16 32 128 256 512; do
    render "$s" "icon_${s}x${s}.png"
    render "$((s * 2))" "icon_${s}x${s}@2x.png"
done

iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
rm -rf "$WORK"
echo "Wrote Resources/AppIcon.icns"
