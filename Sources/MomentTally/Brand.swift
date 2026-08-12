import SwiftUI
import AppKit
import MomentTallyCore

/// The Moment Tally brand: the wordmark — "Moment" in ink, "Tally" carrying
/// the brand gradient — plus the tally-mark brand mark (#201: four gradient
/// bars and a strike, see Resources/AppIcon.svg and the motif exports in
/// Resources/), the accent gradient and partner accents. Gradient stops are
/// the momenttally.com values, kept verbatim so the app and the website
/// masthead read as one thing.
///
/// Typography is system-only for now: the real brand faces (Morganite Pro,
/// Palm Springs) are licensed for web/print but not yet for app embedding —
/// and their files must never be committed here (the repo mirrors to public
/// GitHub, which would be redistribution). Until an app license lands,
/// `display` approximates Morganite with SF compressed-black oblique and
/// `promo` approximates Palm Springs with the system serif. Display-size
/// spots use the real faces anyway, as rasterised art: `wordmarkLockup` /
/// `taglineLockup` load PNG exports of the website lockups, cleared for
/// interim use while the app license is negotiated.
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

    /// The display face: SF compressed black oblique — the closest system
    /// stand-in for Morganite Pro's ultra-condensed heavy oblique (the
    /// website lockup's face) until the app font license is sorted.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed).italic()
    }

    /// The promo face for taglines: system serif italic, standing in for
    /// Palm Springs (the website's headline script) on the same interim
    /// terms as `display`.
    static func promo(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif).italic()
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

    // MARK: Launcher tile gradient (#201)

    /// The Studio launcher-tile recipe, ported verbatim from the website's
    /// `src/lib/launcher.ts` (design doc section 05): stop A is the card's
    /// colour, stop B rotates hue +28° with a small saturation push and a
    /// lightness step down; low-chroma colours ramp lightness instead, so a
    /// grey tile doesn't pick up a phantom hue. CSS's 135deg is topLeading →
    /// bottomTrailing here. Keep the two files in sync.
    static func tileGradient(for color: Color) -> LinearGradient {
        let (h, s, l) = hsl(of: color)
        let stops: [Color] = s < 14
            ? [hslColor(h, s, min(l + 16, 92)), color]
            : [color, hslColor((h + 28).truncatingRemainder(dividingBy: 360),
                               min(s + 6, 96), max(l - 8, 14))]
        return LinearGradient(colors: stops,
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The recipe's glyph colour: ink on light tiles, white otherwise. Only
    /// for tiles drawn with `tileGradient` — flat fills keep
    /// `contrastingTextColor`, whose threshold matches a solid background.
    static func tileGlyph(for color: Color) -> Color {
        hsl(of: color).l > 70 ? .black.opacity(0.68) : .white
    }

    /// CSS-convention HSL (h 0–360, s/l 0–100), matching the web recipe's
    /// `hexToHsl` so both ends derive the same stop B.
    private static func hsl(of color: Color) -> (h: Double, s: Double, l: Double) {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return (0, 0, 0) }
        let r = Double(c.redComponent), g = Double(c.greenComponent),
            b = Double(c.blueComponent)
        let mx = max(r, g, b), mn = min(r, g, b)
        var h = 0.0, s = 0.0
        let l = (mx + mn) / 2
        if mx != mn {
            let d = mx - mn
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
        }
        return (h, s * 100, l * 100)
    }

    private static func hslColor(_ h: Double, _ s: Double, _ l: Double) -> Color {
        let s = s / 100, l = l / 100
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double) = switch hp {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        return Color(.sRGB, red: r1 + m, green: g1 + m, blue: b1 + m)
    }

    /// The tally-mark tile, from the bundled icns (works unbundled, where
    /// `NSApp.applicationIconImage` would be the generic executable icon).
    static var appIcon: NSImage? {
        resources.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
    }

    /// The wordmark as the website actually sets it — real Morganite, ink
    /// "Moment", gradient "Tally" — for display-size spots where `wordmark`'s
    /// system stand-in is most visibly not the brand face. Appearance-keyed
    /// because the renders bake their ink colour in (the masters are
    /// dark-background exports); both variants regenerate from the repo-root
    /// Resources/ masters via scripts/make-lockups.swift.
    static func wordmarkLockup(for scheme: ColorScheme) -> NSImage? {
        lockup("Wordmark", scheme)
    }

    /// "Count what counts." in the real tagline face, on the same terms as
    /// `wordmarkLockup`.
    static func taglineLockup(for scheme: ColorScheme) -> NSImage? {
        lockup("Tagline", scheme)
    }

    private static func lockup(_ name: String, _ scheme: ColorScheme) -> NSImage? {
        resources.url(forResource: "\(name)-\(scheme == .dark ? "dark" : "light")",
                      withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
    }

    /// The tally mark as a menu-bar template image: the favicon's four bars
    /// and strike, monochrome — drawn in code (the favicon geometry, y
    /// flipped for AppKit) rather than shipped as an asset, so there is
    /// nothing to rasterize per scale factor. Template rendering lets the
    /// system tint it for menu-bar state (dark menu bar, highlight, reduced
    /// transparency).
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18),
                            flipped: false) { _ in
            let scale = NSAffineTransform()
            scale.scale(by: 18.0 / 64.0)
            scale.concat()
            let mark = NSBezierPath()
            for x: CGFloat in [11.25, 23.25, 35.25, 47.25] {
                mark.append(NSBezierPath(
                    roundedRect: NSRect(x: x, y: 7, width: 5.5, height: 50),
                    xRadius: 2.75, yRadius: 2.75))
            }
            // SVG's rotate(-27°) about the centre, sign flipped with the axis.
            let rotate = NSAffineTransform()
            rotate.translateX(by: 32, yBy: 32)
            rotate.rotate(byDegrees: 27)
            rotate.translateX(by: -32, yBy: -32)
            let strike = NSBezierPath(
                roundedRect: NSRect(x: 3, y: 29.25, width: 58, height: 5.5),
                xRadius: 2.75, yRadius: 2.75)
            strike.transform(using: rotate as AffineTransform)
            mark.append(strike)
            NSColor.black.setFill()
            mark.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// A colour that follows the appearance the view actually renders in.
    private static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light) ?? .gray)
        })
    }
}
