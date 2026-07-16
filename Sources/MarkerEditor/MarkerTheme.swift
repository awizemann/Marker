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
        // Accent defaults spelled with the PUBLIC sRGB initializer (a public init's default arguments
        // are serialized into clients, so they can't reference the internal `markerHex` helper).
        // Values are hex-per-channel: 0xFFF1A8, 0x142818 α0.05, 0x142818 α0.035, 0xB07A12, 0x2A7C94, 0x0E7D46.
        highlightBackground: Color = Color(.sRGB, red: 0xFF/255.0, green: 0xF1/255.0, blue: 0xA8/255.0, opacity: 1),      // == highlight marker-pen
        tableZebra: Color = Color(.sRGB, red: 0x14/255.0, green: 0x28/255.0, blue: 0x18/255.0, opacity: 0.05),            // faint alternate-row band
        activeLineTint: Color = Color(.sRGB, red: 0x14/255.0, green: 0x28/255.0, blue: 0x18/255.0, opacity: 0.035),       // soft current-line band
        codeString: Color = Color(.sRGB, red: 0xB0/255.0, green: 0x7A/255.0, blue: 0x12/255.0, opacity: 1),   // strings — warm gold, readable on grey
        codeConstant: Color = Color(.sRGB, red: 0x2A/255.0, green: 0x7C/255.0, blue: 0x94/255.0, opacity: 1), // numbers/constants — teal
        codeType: Color = Color(.sRGB, red: 0x0E/255.0, green: 0x7D/255.0, blue: 0x46/255.0, opacity: 1),      // types — deep green
        // System-font DESIGN variants — appended (with defaults) after the original parameters so
        // every existing consumer call site keeps compiling unchanged.
        proseDesign: NSFontDescriptor.SystemDesign? = nil,
        uiDesign: NSFontDescriptor.SystemDesign? = nil
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

extension Color {
    /// 0xRRGGBB initializer for the theme's default accents (internal — MarkerEditor deliberately
    /// does not depend on any consumer design system's `Color(hex:)`).
    ///
    /// Bit layout: red is bits 16–23, green is bits 8–15, blue is bits 0–7.
    /// Each channel is masked to a byte and normalized to 0...1 in the sRGB space.
    init(markerHex hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: alpha)
    }
}
