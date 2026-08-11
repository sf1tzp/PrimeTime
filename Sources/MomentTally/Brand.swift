import SwiftUI
import AppKit
import CoreText
import MomentTallyCore

/// The Moment Tally brand: the Bricolage Grotesque wordmark — "Moment" in
/// ink, "Tally" carrying the brand gradient — plus the accent gradient and
/// partner accents. Wordmark-only for now: the brand-mark motif is still
/// undecided (#195), so nothing here invents a logo mark. Gradient stops are
/// the momenttally.com values, kept verbatim so the app and the website
/// masthead read as one thing.
enum Brand {

    /// The SwiftPM resource bundle. `swift build`'s generated `Bundle.module`
    /// checks only the .app root and the absolute .build path of the machine
    /// that compiled the release — on any other machine it fatalErrors before
    /// the first frame. Look where bundle-app.sh actually puts the bundle
    /// (Contents/Resources), then fall back to `.module` for unbundled
    /// `swift run` builds, where the baked-in .build path is the right one.
    /// Non-private: HelpView's acknowledgements load license texts from here.
    static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?
            .appendingPathComponent("MomentTally_MomentTally.bundle"),
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

    /// "Moment Tally" as the site renders it: "Moment" in ink (whatever the
    /// context's foreground is), brand-gradient "Tally", tight tracking.
    /// A `Text` so it concatenates into sentences.
    static func wordmark(size: CGFloat) -> Text {
        let kern = -size * 0.02   // tracking-tight
        return Text("Moment ").font(display(size)).kerning(kern)
            + Text("Tally").font(display(size)).kerning(kern)
                .foregroundStyle(brandGradient)
    }

    /// The brand gradient — `linear-gradient(90deg, #007aff, #af52de,
    /// #ff2d55, #ff9500)`: blue → purple → pink → orange, horizontal, evenly
    /// spaced stops. System-palette hues that hold up on light and dark
    /// backgrounds alike, so the stops are not appearance-dependent.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "#007aff") ?? .blue,
                Color(hex: "#af52de") ?? .purple,
                Color(hex: "#ff2d55") ?? .pink,
                Color(hex: "#ff9500") ?? .orange,
            ],
            startPoint: .leading, endPoint: .trailing)
    }

    /// The accent gradient — `linear-gradient(135deg, #5856d6, #007aff)`:
    /// indigo into blue, top-left to bottom-right. For flourishes that
    /// should read branded without the full four-stop wordmark gradient.
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "#5856d6") ?? .indigo,
                Color(hex: "#007aff") ?? .blue,
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Traggo's accent (import attribution) — Go's Gopher Blue, nudged
    /// darker on light backgrounds where #00add8 runs out of contrast.
    static let traggoBlue = dynamic(light: "#0087a8", dark: "#00add8")

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
