import SwiftUI
import AppKit
import CoreText
import PrimeTimeCore

/// The PrimeTime brand, ported from primetime-website (`layout.css` +
/// `Nav.svelte`): the Bricolage Grotesque wordmark with the torch-gradient
/// "Time", the app-icon mark, and partner accents. Values mirror the site's
/// oklch fire stops (converted to sRGB) so the app and the website masthead
/// read as one thing.
enum Brand {

    /// The SwiftPM resource bundle. `swift build`'s generated `Bundle.module`
    /// checks only the .app root and the absolute .build path of the machine
    /// that compiled the release — on any other machine it fatalErrors before
    /// the first frame. Look where bundle-app.sh actually puts the bundle
    /// (Contents/Resources), then fall back to `.module` for unbundled
    /// `swift run` builds, where the baked-in .build path is the right one.
    private static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?
            .appendingPathComponent("PrimeTime_PrimeTime.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()

    /// Register the bundled wordmark font (Bricolage Grotesque, OFL — the
    /// license text ships next to it). Process-scoped: nothing is installed
    /// on the user's system. Call once at launch, before any view renders.
    static func registerFonts() {
        guard let url = resources.url(forResource: "BricolageGrotesque",
                                      withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// The display face at the website's wordmark weight (`font-extrabold`).
    /// The named variable-font instance resolves after `registerFonts()`.
    static func display(_ size: CGFloat) -> Font {
        .custom("BricolageGrotesque-ExtraBold", size: size)
    }

    /// "PrimeTime" as the site renders it: solid "Prime", torch-gradient
    /// "Time", tight tracking. A `Text` so it concatenates into sentences.
    static func wordmark(size: CGFloat) -> Text {
        let kern = -size * 0.02   // tracking-tight
        return Text("Prime").font(display(size)).kerning(kern)
            + Text("Time").font(display(size)).kerning(kern)
                .foregroundStyle(torchGradient)
    }

    /// `--torch-grad`: ember → flame → gold → spark at 100° (near-horizontal,
    /// slightly falling). Light stops are the site's darker `:root` fire so
    /// the gradient keeps contrast on a light background.
    static var torchGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: dynamic(light: "#c2410c", dark: "#f25914"), location: 0),
                .init(color: dynamic(light: "#d1560b", dark: "#fe860f"), location: 0.42),
                .init(color: dynamic(light: "#ca8a04", dark: "#f8bd40"), location: 0.78),
                .init(color: dynamic(light: "#eab308", dark: "#f9e03f"), location: 1),
            ],
            startPoint: UnitPoint(x: 0, y: 0.42),
            endPoint: UnitPoint(x: 1, y: 0.58))
    }

    /// Traggo's accent from primetime.tools/attributions — Go's Gopher Blue,
    /// nudged darker on light backgrounds where #00add8 runs out of contrast.
    static let traggoBlue = dynamic(light: "#0087a8", dark: "#00add8")

    /// The torch gradient's gold stop as a standalone accent — for small
    /// flourishes that should read as "brand fire" without the full gradient.
    static let torchGold = dynamic(light: "#ca8a04", dark: "#f8bd40")

    /// The flaming-clock mark, from the bundled icns (works unbundled, where
    /// `NSApp.applicationIconImage` would be the generic executable icon).
    static var appIcon: NSImage? {
        resources.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
    }

    /// A colour that follows the appearance the view actually renders in.
    private static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light) ?? .gray)
        })
    }
}
