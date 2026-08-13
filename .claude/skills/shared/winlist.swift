import CoreGraphics
import Foundation

// winlist [ownerFilter] — prints windowID|owner|name|x,y,w,h for on-screen windows
let filter = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    if let f = filter, !owner.localizedCaseInsensitiveContains(f) { continue }
    let id = w[kCGWindowNumber as String] as? Int ?? 0
    let name = w[kCGWindowName as String] as? String ?? ""
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    print("\(id)|\(owner)|\(name)|\(Int(b["X"] ?? 0)),\(Int(b["Y"] ?? 0)),\(Int(b["Width"] ?? 0)),\(Int(b["Height"] ?? 0))")
}
