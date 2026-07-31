#!/usr/bin/env bash
# Render Resources/AppIcon.svg into Resources/AppIcon.icns via a tiny inline
# Swift rasterizer (NSImage reads SVG natively) + iconutil — still no
# third-party rasterizer. qlmanage, the previous approach, composites SVG
# thumbnails on white, which matted the tile's transparent corners (visible
# once onboarding drew the icon on a window background).
# The .icns is checked in so CI never runs this; re-run it after editing
# the SVG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/Resources/AppIcon.svg"
WORK="$(mktemp -d)"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"

cat > "$WORK/render.swift" <<'EOF'
import AppKit
// render <svg> <px> <out.png> — rasterize with alpha preserved
let args = CommandLine.arguments
guard args.count == 4, let px = Int(args[2]),
      let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else { exit(1) }
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
           from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: args[3]))
EOF
swiftc -O -o "$WORK/render" "$WORK/render.swift"

for s in 16 32 128 256 512; do
    "$WORK/render" "$SVG" "$s" "$SET/icon_${s}x${s}.png"
    "$WORK/render" "$SVG" "$((s * 2))" "$SET/icon_${s}x${s}@2x.png"
done

iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
rm -rf "$WORK"
echo "Wrote Resources/AppIcon.icns"
