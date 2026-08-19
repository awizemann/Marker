import Testing
import AppKit
import SwiftUI
@testable import Marker
@testable import MarkerEditor

/// Appearance adaptivity, end to end.
///
/// The load-bearing claim these tests defend: a theme color built with `MarkerTheme.adaptive` wraps a
/// DYNAMIC `NSColor`, and that dynamism survives the `Color` → `NSColor(Color)` round trip every
/// AppKit call site in the editor makes, and survives being parked in an `NSAttributedString`
/// attribute. So `EditorStyler` can keep styling once and the SAME storage renders light or dark.
/// (Verified empirically before this was written — if AppKit ever flattened the round trip, these
/// tests go red rather than the editor silently freezing in light mode.)
@MainActor
@Suite("Appearance-adaptive theme")
struct AdaptiveThemeTests {

    // MARK: Resolution helpers

    /// Resolve a color under a named appearance and hand back its sRGB components.
    private static func resolve(_ color: NSColor,
                                _ name: NSAppearance.Name) -> (r: Double, g: Double, b: Double, a: Double) {
        var out = (r: -1.0, g: -1.0, b: -1.0, a: -1.0)
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            out = (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        }
        return out
    }

    private static func expectComponents(_ color: NSColor, _ name: NSAppearance.Name,
                                         hex: UInt, alpha: Double = 1,
                                         _ label: Comment, sourceLocation: SourceLocation = #_sourceLocation) {
        let got = resolve(color, name)
        let want = (r: Double((hex >> 16) & 0xFF) / 255,
                    g: Double((hex >> 8) & 0xFF) / 255,
                    b: Double(hex & 0xFF) / 255)
        #expect(abs(got.r - want.r) < 0.01, label, sourceLocation: sourceLocation)
        #expect(abs(got.g - want.g) < 0.01, label, sourceLocation: sourceLocation)
        #expect(abs(got.b - want.b) < 0.01, label, sourceLocation: sourceLocation)
        #expect(abs(got.a - alpha) < 0.01, label, sourceLocation: sourceLocation)
    }

    // MARK: Fixture

    /// TrapperKeeper's own light/dark values for the core palette; accents stay at MarkerTheme's
    /// defaults so the default-value assertions below exercise the shipped numbers.
    private static let theme = MarkerTheme(
        ink:     .adaptiveInk,
        inkSoft: MarkerTheme.adaptive(light: 0x2C3A33, dark: 0xC6D4CB),
        muted:   MarkerTheme.adaptive(light: 0x5C6B63, dark: 0x9AAEA1),
        faint:   MarkerTheme.adaptive(light: 0x93A097, dark: 0x7E9187),
        deep:    MarkerTheme.adaptive(light: 0x0E7D46, dark: 0x4BDA8D),
        bright:  MarkerTheme.adaptive(light: 0x1FBE6A, dark: 0x1FBE6A),
        primary: MarkerTheme.adaptive(light: 0x12A45B, dark: 0x1FBE6A),
        well:    MarkerTheme.adaptive(light: 0x142818, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.05),
        line:    MarkerTheme.adaptive(light: 0x142818, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.09),
        sheet:   MarkerTheme.adaptive(light: 0xFFFFFF, dark: 0x0C110E)
    )

    /// A token provider that reports the `"hi"` literal in the fixture's code block as a string token,
    /// so the `codeString` accent actually lands in storage (no tree-sitter needed).
    private final class StringTokenStub: CodeTokenProviding {
        func tokens(for code: String, language: String) -> [HighlightToken] {
            let range = (code as NSString).range(of: "\"hi\"")
            guard range.location != NSNotFound else { return [] }
            return [HighlightToken(range: range, capture: "string")]
        }
    }

    private static let text = """
    # Title

    Body text.

    ```swift
    let s = "hi"
    ```

    - [ ] a task
    - [x] done task

    """

    /// Style the fixture once and return the storage every assertion reads.
    private static func styledStorage() -> NSTextStorage {
        let model = EditorModel(text: text)
        model.hideMarkers = false   // keep the literal `[ ]` cell colored rather than painted clear
        let storage = NSTextStorage(string: text)
        EditorStyler(theme: theme, highlighter: StringTokenStub()).apply(to: storage, model: model)
        return storage
    }

    private static func foreground(at index: Int, in storage: NSTextStorage) throws -> NSColor {
        try #require(storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor)
    }

    private static func index(of needle: String, offset: Int = 0) -> Int {
        (text as NSString).range(of: needle).location + offset
    }

    // MARK: Storage-level: the same attributed string renders two ways

    @Test("Heading and body ink resolve light vs dark from ONE styling pass")
    func inkAdaptsInStorage() throws {
        let storage = Self.styledStorage()
        for (label, idx) in [("heading", Self.index(of: "Title")), ("paragraph", Self.index(of: "Body text"))] {
            let color = try Self.foreground(at: idx, in: storage)
            let light = Self.resolve(color, .aqua), dark = Self.resolve(color, .darkAqua)
            #expect(light != dark, "\(label) ink froze — the Color→NSColor round trip lost its dynamism")
            Self.expectComponents(color, .aqua, hex: 0x16241D, "\(label) light ink")
            Self.expectComponents(color, .darkAqua, hex: 0xE9F1EB, "\(label) dark ink")
        }
    }

    @Test("A code-block string token carries the adaptive codeString accent")
    func codeStringTokenAdapts() throws {
        let storage = Self.styledStorage()
        let color = try Self.foreground(at: Self.index(of: "\"hi\"", offset: 1), in: storage)
        Self.expectComponents(color, .aqua, hex: 0xB07A12, "codeString light — warm gold")
        Self.expectComponents(color, .darkAqua, hex: 0xE5BB72, "codeString dark — lifted gold")
    }

    @Test("Task markers adapt: unchecked takes muted, checked takes primary")
    func taskMarkersAdapt() throws {
        let storage = Self.styledStorage()
        let unchecked = try Self.foreground(at: Self.index(of: "- [ ]"), in: storage)
        Self.expectComponents(unchecked, .aqua, hex: 0x5C6B63, "unchecked marker light (muted)")
        Self.expectComponents(unchecked, .darkAqua, hex: 0x9AAEA1, "unchecked marker dark (muted)")

        let checked = try Self.foreground(at: Self.index(of: "- [x]"), in: storage)
        Self.expectComponents(checked, .aqua, hex: 0x12A45B, "checked marker light (primary)")
        Self.expectComponents(checked, .darkAqua, hex: 0x1FBE6A, "checked marker dark (primary)")
    }

    @Test("The code block's neutral base ink adapts too")
    func codeBaseInkAdapts() throws {
        let storage = Self.styledStorage()
        let color = try Self.foreground(at: Self.index(of: "let s"), in: storage)
        Self.expectComponents(color, .aqua, hex: 0x2C3A33, "code base light (inkSoft)")
        Self.expectComponents(color, .darkAqua, hex: 0xC6D4CB, "code base dark (inkSoft)")
    }

    // MARK: The shipped accent defaults

    @Test("Accent defaults resolve to the specified light and dark values")
    func accentDefaults() {
        let t = MarkerTheme.fallback   // built with every accent left at its default
        let cases: [(String, Color, (UInt, Double), (UInt, Double))] = [
            ("highlightBackground", t.highlightBackground, (0xFFF1A8, 1.0),  (0xE9BB72, 0.30)),
            ("tableZebra",          t.tableZebra,          (0x142818, 0.05), (0xFFFFFF, 0.05)),
            ("activeLineTint",      t.activeLineTint,      (0x142818, 0.035),(0x1FBE6A, 0.08)),
            ("codeString",          t.codeString,          (0xB07A12, 1.0),  (0xE5BB72, 1.0)),
            ("codeConstant",        t.codeConstant,        (0x2A7C94, 1.0),  (0x74CEE2, 1.0)),
            ("codeType",            t.codeType,            (0x0E7D46, 1.0),  (0x4BDA8D, 1.0)),
        ]
        for (name, color, light, dark) in cases {
            let ns = NSColor(color)
            Self.expectComponents(ns, .aqua, hex: light.0, alpha: light.1, "\(name) light")
            Self.expectComponents(ns, .darkAqua, hex: dark.0, alpha: dark.1, "\(name) dark")
        }
    }

    @Test("Dark accents genuinely differ from light — no silently-frozen default")
    func accentDefaultsDiffer() {
        let t = MarkerTheme.fallback
        for (name, color) in [("highlightBackground", t.highlightBackground), ("tableZebra", t.tableZebra),
                              ("activeLineTint", t.activeLineTint), ("codeString", t.codeString),
                              ("codeConstant", t.codeConstant), ("codeType", t.codeType)] {
            let ns = NSColor(color)
            #expect(Self.resolve(ns, .aqua) != Self.resolve(ns, .darkAqua), "\(name) resolves the same in both appearances")
        }
    }

    @Test("adaptive() honours per-side alpha independently")
    func adaptiveAlphas() {
        let color = NSColor(MarkerTheme.adaptive(light: 0x102030, lightAlpha: 0.25, dark: 0xA0B0C0, darkAlpha: 0.75))
        Self.expectComponents(color, .aqua, hex: 0x102030, alpha: 0.25, "light side")
        Self.expectComponents(color, .darkAqua, hex: 0xA0B0C0, alpha: 0.75, "dark side")
    }
}

private extension Color {
    static let adaptiveInk = MarkerTheme.adaptive(light: 0x16241D, dark: 0xE9F1EB)
}
