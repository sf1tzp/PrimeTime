import CoreGraphics
import Foundation

// smoothdrag x1 y1 x2 y2 [durationMs=900] — a drag as macOS actually sees
// one: mouseDown, ~60Hz interpolated mouseDragged stream, a settle pause
// over the target, then mouseUp at the same spot.
let a = CommandLine.arguments.compactMap { Double($0) }
guard a.count >= 4 else { fputs("usage: smoothdrag x1 y1 x2 y2 [ms]\n", stderr); exit(2) }
let (x1, y1, x2, y2) = (a[0], a[1], a[2], a[3])
let ms = a.count >= 5 ? a[4] : 900

func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p,
            mouseButton: .left)?.post(tap: .cghidEventTap)
}

let start = CGPoint(x: x1, y: y1)
let end = CGPoint(x: x2, y: y2)
post(.mouseMoved, start)
usleep(200_000)
post(.leftMouseDown, start)
usleep(120_000)
let steps = max(20, Int(ms / 16))
for i in 1...steps {
    let t = Double(i) / Double(steps)
    // ease-in-out so the pickup and the approach are gentle
    let e = t * t * (3 - 2 * t)
    let p = CGPoint(x: x1 + (x2 - x1) * e, y: y1 + (y2 - y1) * e)
    post(.leftMouseDragged, p)
    usleep(16_000)
}
// settle over the target so dropUpdated has cycles to accept
for _ in 0..<8 {
    post(.leftMouseDragged, end)
    usleep(60_000)
}
post(.leftMouseUp, end)
