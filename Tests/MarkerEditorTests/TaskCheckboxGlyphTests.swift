import Testing
import AppKit
import SwiftUI
@testable import Marker
@testable import MarkerEditor

/// The drawn task-checkbox glyph: checked is a ✓ on a square FILLED with the primary accent, empty is
/// an unfilled square stroked in `checkEmpty`. Both tints come from appearance-adaptive theme tokens,
/// so the two states must render differently AND the tokens must resolve to the handoff's values.
@MainActor
@Suite("Task checkbox glyph")
struct TaskCheckboxGlyphTests {

    // MARK: Helpers

    /// Rasterize an NSImage into a fixed-size sRGB bitmap and hand back its raw pixels, so two
    /// symbol images can be compared by what they actually PAINT rather than by object identity.
    private static func pixels(_ image: NSImage, side: Int = 32) throws -> Data {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// Rasterize and count the fully-opaque pure-red and pure-blue pixels — the two probe tints the
    /// layer-order test feeds in as the palette.
    private static func redBlueCounts(_ image: NSImage, side: Int = 64) throws -> (red: Int, blue: Int) {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        var out = (red: 0, blue: 0)
        for x in 0..<side {
            for y in 0..<side {
                guard let px = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), px.alphaComponent > 0.9 else { continue }
                if px.redComponent > 0.9, px.greenComponent < 0.1, px.blueComponent < 0.1 { out.red += 1 }
                if px.blueComponent > 0.9, px.redComponent < 0.1, px.greenComponent < 0.1 { out.blue += 1 }
            }
        }
        return out
    }

    private static func resolve(_ color: Color, _ name: NSAppearance.Name) throws -> (Double, Double, Double, Double) {
        var out = (-1.0, -1.0, -1.0, -1.0)
        let appearance = try #require(NSAppearance(named: name))
        appearance.performAsCurrentDrawingAppearance {
            if let c = NSColor(color).usingColorSpace(.sRGB) {
                out = (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
            }
        }
        return out
    }

    private static func expect(_ color: Color, _ name: NSAppearance.Name, hex: UInt,
                               _ label: Comment, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let got = try resolve(color, name)
        let want = (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        #expect(abs(got.0 - want.0) < 0.01, label, sourceLocation: sourceLocation)
        #expect(abs(got.1 - want.1) < 0.01, label, sourceLocation: sourceLocation)
        #expect(abs(got.2 - want.2) < 0.01, label, sourceLocation: sourceLocation)
        #expect(abs(got.3 - 1.0) < 0.01, label, sourceLocation: sourceLocation)
    }

    private static let theme = MarkerTheme.fallback   // every checkbox token left at its default

    private static func image(checked: Bool, _ name: NSAppearance.Name) throws -> NSImage {
        let palette: [NSColor] = checked
            ? [NSColor(theme.onAccent), NSColor(theme.primary)]
            : [NSColor(theme.checkEmpty)]
        let appearance = try #require(NSAppearance(named: name))
        return try #require(CodeWellTextView.checkboxImage(checked: checked, palette: palette, side: 14,
                                                           appearance: appearance))
    }

    // MARK: The tokens

    @Test("onAccent resolves white on light and the near-black green on dark")
    func onAccentValues() throws {
        try Self.expect(Self.theme.onAccent, .aqua, hex: 0xFFFFFF, "onAccent light")
        try Self.expect(Self.theme.onAccent, .darkAqua, hex: 0x062012, "onAccent dark")
    }

    @Test("checkEmpty resolves the light and dark border greys")
    func checkEmptyValues() throws {
        try Self.expect(Self.theme.checkEmpty, .aqua, hex: 0xC7D0C9, "checkEmpty light")
        try Self.expect(Self.theme.checkEmpty, .darkAqua, hex: 0x48584F, "checkEmpty dark")
    }

    @Test("Both checkbox tokens genuinely differ between appearances")
    func tokensAdapt() throws {
        for (label, color) in [("onAccent", Self.theme.onAccent), ("checkEmpty", Self.theme.checkEmpty)] {
            let light = try Self.resolve(color, .aqua), dark = try Self.resolve(color, .darkAqua)
            #expect(light != dark, "\(label) resolves identically in both appearances")
        }
    }

    // MARK: The rendered glyph

    @Test("Checked and unchecked render to different, non-blank images")
    func checkedDiffersFromEmpty() throws {
        let blank = try Self.pixels(NSImage(size: NSSize(width: 14, height: 14)))
        let checked = try Self.pixels(Self.image(checked: true, .aqua))
        let empty = try Self.pixels(Self.image(checked: false, .aqua))
        // Guard against a vacuous pass: if the symbols painted nothing, both would equal `blank`
        // and the inequality below would be comparing two empty canvases.
        #expect(checked != blank, "the checked symbol painted nothing")
        #expect(empty != blank, "the empty symbol painted nothing")
        #expect(checked != empty, "the filled ✓ square and the empty square rasterize identically")
    }

    @Test("Palette order is glyph-then-fill: onAccent paints the ✓, primary the square")
    func paletteLayerOrder() throws {
        // Probe with unmistakable colors: red in the onAccent slot, blue in the primary slot. The
        // square's fill covers far more area than the checkmark, so blue must dominate — if the
        // symbol's layer order were the other way round, the ✓ would be blue and the square red.
        let appearance = try #require(NSAppearance(named: .aqua))
        let image = try #require(CodeWellTextView.checkboxImage(checked: true, palette: [.red, .blue],
                                                                side: 14, appearance: appearance))
        let n = try Self.redBlueCounts(image)
        #expect(n.blue > n.red, "the primary slot did not paint the square fill (red \(n.red) vs blue \(n.blue))")
        #expect(n.red > 0, "the onAccent slot painted no checkmark pixels")
    }

    @Test("The same state renders differently under aqua vs darkAqua")
    func appearanceChangesTheGlyph() throws {
        for checked in [true, false] {
            let light = try Self.pixels(Self.image(checked: checked, .aqua))
            let dark = try Self.pixels(Self.image(checked: checked, .darkAqua))
            #expect(light != dark, "checked=\(checked) baked the same tint in both appearances")
        }
    }

    @Test("The cache serves the same image back for an identical request, and a distinct one otherwise")
    func cacheKeysOnStateAndPalette() throws {
        let a = try Self.image(checked: true, .aqua)
        let b = try Self.image(checked: true, .aqua)
        #expect(a === b, "identical request re-rendered instead of hitting the cache")
        #expect(try Self.image(checked: true, .darkAqua) !== a, "the dark render collided with the light cache entry")
        #expect(try Self.image(checked: false, .aqua) !== a, "the empty render collided with the checked cache entry")
    }
}
