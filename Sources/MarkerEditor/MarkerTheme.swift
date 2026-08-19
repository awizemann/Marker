import AppKit
import SwiftUI

/// Design tokens the editor renders with. Consumers build one from their app's design system.
///
/// The palette names mirror the roles the editor needs (ink for body text, well/line for the code
/// box, sheet for grid-table backgrounds, primary for links/accents…); the accent slots default to
/// values tuned for a light, slightly-green neutral palette and can be overridden per-app. Font
/// families are resolved BY NAME with a system fallback — consumers bundle their own font files.
public struct MarkerTheme: Sendable {
    // Core palette
    public var ink: Color
    public var inkSoft: Color
    public var muted: Color
    public var faint: Color
    public var deep: Color
    public var bright: Color
    public var primary: Color
    public var well: Color
    public var line: Color
    public var sheet: Color
    // Font families (resolved by name with system fallback — consumers bundle their own fonts)
    public var proseFamily: String?   // nil → system font
    public var monoFamily: String?    // nil → monospaced system font
    public var uiFamily: String?      // nil → system font (table grid cells, placeholder captions)
    // Font designs — the SYSTEM font's design variant (.serif, .rounded, …) for apps that want a
    // designed system face without bundling a family. Resolution rule: an explicit family name WINS;
    // else a set design yields the system font with that design; else the plain system font.
    public var proseDesign: NSFontDescriptor.SystemDesign?   // nil → plain system (when proseFamily is nil)
    public var uiDesign: NSFontDescriptor.SystemDesign?      // nil → plain system (when uiFamily is nil)
    // Editor accents (sensible defaults; override if your palette needs)
    public var highlightBackground: Color
    public var tableZebra: Color
    public var activeLineTint: Color
    public var codeString: Color
    public var codeConstant: Color
    public var codeType: Color
    /// Foreground riding ON the primary accent — the ✓ inside a filled task checkbox.
    public var onAccent: Color
    /// The 1.5px border of an EMPTY task checkbox (no fill).
    public var checkEmpty: Color

    public init(
        ink: Color,
        inkSoft: Color,
        muted: Color,
        faint: Color,
        deep: Color,
        bright: Color,
        primary: Color,
        well: Color,
        line: Color,
        sheet: Color,
        proseFamily: String? = nil,
        monoFamily: String? = nil,
        uiFamily: String? = nil,
        // Accent defaults — the appearance-adaptive `MarkerTheme.default…` tokens below (public
        // statics, so a public init's default args can reference them; built ONCE, so constructing
        // a theme doesn't mint fresh dynamic colors each time).
        highlightBackground: Color = MarkerTheme.defaultHighlightBackground,
        tableZebra: Color = MarkerTheme.defaultTableZebra,
        activeLineTint: Color = MarkerTheme.defaultActiveLineTint,
        codeString: Color = MarkerTheme.defaultCodeString,
        codeConstant: Color = MarkerTheme.defaultCodeConstant,
        codeType: Color = MarkerTheme.defaultCodeType,
        // System-font DESIGN variants — appended (with defaults) after the original parameters so
        // every existing consumer call site keeps compiling unchanged.
        proseDesign: NSFontDescriptor.SystemDesign? = nil,
        uiDesign: NSFontDescriptor.SystemDesign? = nil,
        // Task-checkbox tokens — appended (with defaults) so existing call sites keep compiling.
        onAccent: Color = MarkerTheme.defaultOnAccent,
        checkEmpty: Color = MarkerTheme.defaultCheckEmpty
    ) {
        self.ink = ink
        self.inkSoft = inkSoft
        self.muted = muted
        self.faint = faint
        self.deep = deep
        self.bright = bright
        self.primary = primary
        self.well = well
        self.line = line
        self.sheet = sheet
        self.proseFamily = proseFamily
        self.monoFamily = monoFamily
        self.uiFamily = uiFamily
        self.highlightBackground = highlightBackground
        self.tableZebra = tableZebra
        self.activeLineTint = activeLineTint
        self.codeString = codeString
        self.codeConstant = codeConstant
        self.codeType = codeType
        self.proseDesign = proseDesign
        self.uiDesign = uiDesign
        self.onAccent = onAccent
        self.checkEmpty = checkEmpty
    }

    /// A pre-wiring default built from system-ish colors — used only so views (CodeWellTextView) have
    /// a valid theme before the host injects the real one. Exact values are deliberately unexciting.
    public static let fallback = MarkerTheme(
        ink: .primary,
        inkSoft: .primary.opacity(0.85),
        muted: .secondary,
        faint: Color(nsColor: .tertiaryLabelColor),
        deep: .accentColor,
        bright: .accentColor,
        primary: .accentColor,
        well: Color(nsColor: .windowBackgroundColor),
        line: Color(nsColor: .separatorColor),
        sheet: Color(nsColor: .textBackgroundColor)
    )
}

// MARK: - Appearance-adaptive colors

extension MarkerTheme {

    /// Build an **appearance-adaptive** color from two hex values — the light one resolves under
    /// `.aqua`, the dark one under `.darkAqua`.
    ///
    /// Same shape as TrapperKeeper's `TKColor.adaptive`, exposed publicly so a consumer WITHOUT that
    /// design system can still build an adaptive `MarkerTheme` (and so this type's own accent
    /// defaults — which are inlined into clients — have a public spelling to use).
    ///
    /// The result wraps a dynamic `NSColor`, which survives the `Color` → `NSColor` round trip the
    /// editor's AppKit call sites make: it stays dynamic and re-resolves per drawing appearance, so
    /// nothing downstream has to plumb an appearance through.
    public static func adaptive(light: UInt, lightAlpha: Double = 1,
                                dark: UInt, darkAlpha: Double = 1) -> Color {
        let lightColor = NSColor(markerHex: light, alpha: lightAlpha)
        let darkColor = NSColor(markerHex: dark, alpha: darkAlpha)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        })
    }
}

// MARK: - Default accent tokens (appearance-adaptive; light values are the original palette)

public extension MarkerTheme {
    /// Highlight marker-pen (`==text==`): pale yellow on light, amber wash on dark.
    static let defaultHighlightBackground = MarkerTheme.adaptive(light: 0xFFF1A8, dark: 0xE9BB72, darkAlpha: 0.30)
    /// Faint alternate-row band in grid tables — hairline family, flips polarity on dark.
    static let defaultTableZebra = MarkerTheme.adaptive(light: 0x142818, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.05)
    /// Soft current-line band: ink wash on light, the design's green-tinted lift on dark.
    static let defaultActiveLineTint = MarkerTheme.adaptive(light: 0x142818, lightAlpha: 0.035, dark: 0x1FBE6A, darkAlpha: 0.08)
    /// Code strings — warm gold.
    static let defaultCodeString = MarkerTheme.adaptive(light: 0xB07A12, dark: 0xE5BB72)
    /// Code numbers/constants — teal.
    static let defaultCodeConstant = MarkerTheme.adaptive(light: 0x2A7C94, dark: 0x74CEE2)
    /// Code types — accent-text green (the "deep" step, which lightens on dark).
    static let defaultCodeType = MarkerTheme.adaptive(light: 0x0E7D46, dark: 0x4BDA8D)
    /// Ink drawn ON the accent (the ✓ in a checked task box): white on light, near-black on dark.
    static let defaultOnAccent = MarkerTheme.adaptive(light: 0xFFFFFF, dark: 0x062012)
    /// Border of an empty task box.
    static let defaultCheckEmpty = MarkerTheme.adaptive(light: 0xC7D0C9, dark: 0x48584F)
}

// MARK: - Font resolution (theme families, system fallback)

extension MarkerTheme {

    /// The prose (body/heading) NSFont at a size/weight — the theme's `proseFamily` (an explicit
    /// family always wins), else the system font in `proseDesign` (when set), else the system font.
    func proseNSFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        Self.resolved(proseFamily, size: size, weight: weight,
                      fallback: Self.systemFont(size: size, weight: weight, design: proseDesign))
    }

    /// The mono (code/table-source) NSFont at a size/weight — the theme's `monoFamily`, or system mono.
    func monoNSFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        Self.resolved(monoFamily, size: size, weight: weight, fallback: .monospacedSystemFont(ofSize: size, weight: weight))
    }

    /// The SwiftUI mono font (palette symbols, hints, keycaps) — the theme's `monoFamily` by name
    /// (SwiftUI's `.custom` silently falls back to the system font if the family isn't installed),
    /// else the monospaced system font.
    func monoFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let monoFamily else { return .system(size: size, weight: weight, design: .monospaced) }
        return .custom(monoFamily, size: size).weight(weight)
    }

    /// The SwiftUI UI font (grid-table cells, placeholder captions) — the theme's `uiFamily` by name
    /// (SwiftUI's `.custom` silently falls back to the system font if the family isn't installed),
    /// else the system font in `uiDesign` (when set and mappable to `Font.Design`), else the system font.
    func uiFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let uiFamily else {
            return .system(size: size, weight: weight, design: Self.fontDesign(uiDesign) ?? .default)
        }
        return .custom(uiFamily, size: size).weight(weight)
    }

    /// The system NSFont at a size/weight, in an optional design variant (.serif, .rounded, …).
    /// A design whose descriptor doesn't resolve (nil `withDesign` result) falls back to the plain
    /// system font, so a theme can never end up font-less.
    static func systemFont(size: CGFloat, weight: NSFont.Weight, design: NSFontDescriptor.SystemDesign?) -> NSFont {
        let plain = NSFont.systemFont(ofSize: size, weight: weight)
        guard let design, design != .default else { return plain }
        guard let descriptor = plain.fontDescriptor.withDesign(design),
              let designed = NSFont(descriptor: descriptor, size: size) else { return plain }
        return designed
    }

    /// Map an AppKit `SystemDesign` onto SwiftUI's `Font.Design` for the SwiftUI ui-font path.
    /// nil for designs SwiftUI has no counterpart for.
    static func fontDesign(_ design: NSFontDescriptor.SystemDesign?) -> Font.Design? {
        switch design {
        case .default:    return .default
        case .serif:      return .serif
        case .rounded:    return .rounded
        case .monospaced: return .monospaced
        default:          return nil
        }
    }

    /// Resolve a family name to an NSFont at a size/weight, or `fallback` when the family is nil /
    /// not installed (same pattern as the original EditorStyling `resolved`).
    private static func resolved(_ family: String?, size: CGFloat, weight: NSFont.Weight, fallback: NSFont) -> NSFont {
        guard let family else { return fallback }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
        ])
        if let font = NSFont(descriptor: descriptor, size: size), font.familyName == family {
            return font
        }
        return fallback
    }
}

// MARK: - Internal hex color helper

extension NSColor {
    /// 0xRRGGBB initializer in the sRGB space — used to build the two branches of an adaptive dynamic
    /// color. Internal on purpose: MarkerEditor deliberately does not depend on any consumer design
    /// system's `Color(hex:)`, and `adaptive` is the public door onto this.
    ///
    /// Bit layout: red is bits 16–23, green is bits 8–15, blue is bits 0–7; each channel is masked to
    /// a byte and normalized to 0...1.
    convenience init(markerHex hex: UInt, alpha: Double = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green:   CGFloat((hex >> 8)  & 0xFF) / 255,
                  blue:    CGFloat( hex        & 0xFF) / 255,
                  alpha:   CGFloat(alpha))
    }
}
