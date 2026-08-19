import Testing
import AppKit
import SwiftUI
@testable import Marker
@testable import MarkerEditor

/// REAL rendered verification of appearance-adaptive theming.
///
/// Every other appearance test in this target reads *attributes* (a color object resolved under an
/// appearance). This one builds the real editor view stack, lays it out, rasterizes it under `.aqua`
/// and `.darkAqua`, and samples PIXELS — so a regression that leaves the tokens correct but paints
/// the wrong thing (a baked-light checkbox cache, a well that never repaints, a frozen ink) goes red
/// here even while the attribute tests stay green.
///
/// ## What was required to make an offscreen render honor the appearance (findings)
///
/// Three things, none of them obvious, all needed together:
///
/// 1. **`view.appearance = NSAppearance(named:)` is necessary but NOT sufficient.** It fixes
///    `effectiveAppearance` (which is what `CodeWellTextView.drawTaskCheckboxes` resolves the
///    checkbox palette under, explicitly), but `cacheDisplay(in:to:)` does not install that
///    appearance as the CURRENT DRAWING appearance. Dynamic `NSColor`s resolved implicitly inside
///    `draw(_:)` — the well fill, the border, NSTextView's own attributed-string foregrounds —
///    would then fall back to whatever is current (light), and the "dark" render comes back light.
///    Wrapping the rasterization in `appearance.performAsCurrentDrawingAppearance { … }` fixes it.
///
/// 2. **The view must be hosted in a window.** `drawTaskCheckboxes` culls each cell against
///    `visibleRect`, and a view with no window has an EMPTY visible rect — so a window-less
///    `cacheDisplay` draws the wells and the text but SILENTLY no checkboxes. An offscreen
///    borderless `NSWindow` (never ordered front) is enough. This is a trap, not a bug: on screen
///    the cull is exactly right.
///
/// 3. **The sheet must be painted by a container view BEHIND the text view**, as the SwiftUI host
///    does — not by turning the text view's own `drawsBackground` on. NSTextView paints its
///    background inside `super.draw(_:)`, which `CodeWellTextView.draw(_:)` calls LAST (glyphs on
///    top), so an opaque text-view background covers the wells, the current-line tint and the
///    checkboxes, and the render comes back blank exactly where the themed decoration should be.
///
/// A consumer app hits none of this. It is purely an offscreen-render obligation, recorded here so
/// the next person rendering the editor headless does not conclude the theming is broken.
///
/// Sampling note: exact composites are deliberately not asserted. AppKit blends into the bitmap's
/// own color space (a 5%-alpha well reads a few percent stronger than the naive sRGB mix) and a
/// 14pt SF Symbol is heavily antialiased, so the assertions pin DIRECTION (which side of the sheet
/// the well sits on), HUE (green-channel dominance for the accent, neutrality for the border) and
/// light-vs-dark DIFFERENCE, with tolerances wide enough to survive AppKit's rendering details and
/// tight enough to fail on a wrong token.
@MainActor
@Suite("Rendered appearance (pixels)")
struct RenderedAppearanceTests {

    // MARK: - Fixture

    /// TrapperKeeper's palette, in `MarkerTheme.adaptive` form (the handoff values).
    static let theme = MarkerTheme(
        ink:     MarkerTheme.adaptive(light: 0x16241D, dark: 0xE9F1EB),
        inkSoft: MarkerTheme.adaptive(light: 0x2C3A33, dark: 0xC6D4CB),
        muted:   MarkerTheme.adaptive(light: 0x5C6B63, dark: 0x9AAEA1),
        faint:   MarkerTheme.adaptive(light: 0x93A097, dark: 0x7E9187),
        deep:    MarkerTheme.adaptive(light: 0x0E7D46, dark: 0x4BDA8D),
        bright:  MarkerTheme.adaptive(light: 0x12A45B, dark: 0x1FBE6A),
        primary: MarkerTheme.adaptive(light: 0x12A45B, dark: 0x1FBE6A),
        well:    MarkerTheme.adaptive(light: 0x142818, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.05),
        line:    MarkerTheme.adaptive(light: 0x142818, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.09),
        sheet:   MarkerTheme.adaptive(light: 0xFFFFFF, dark: 0x0C110E)
    )

    static let markdown = """
    # Rendered check

    A paragraph of prose that sits on the sheet.

    ```swift
    let greeting = "hi"
    ```

    - [ ] an unchecked task
    - [x] a checked task

    """

    // MARK: - The view stack (EditorView's own seams, driven headless)

    /// Build the real TextKit 2 stack `EditorView.makeNSView` builds, style it with the real
    /// `EditorStyler`, and wire the three overlay inputs through `EditorView`'s own static seams.
    ///
    /// The editor itself paints NO background (`drawsBackground = false` on both the text view and
    /// the scroll view) — the sheet is the SwiftUI host's, painted BEHIND the editor. So the harness
    /// stands in for the host: a plain container view fills `theme.sheet` and the text view is its
    /// subview. Turning the text view's own `drawsBackground` on instead would be wrong AND useless:
    /// NSTextView paints its background inside `super.draw(_:)`, which `CodeWellTextView.draw` calls
    /// LAST — so the wells, the current-line tint and the checkboxes all end up underneath it and the
    /// render comes back blank where the decorations should be.
    static func makeEditor(width: CGFloat = 620, height: CGFloat = 460) -> (view: CodeWellTextView,
                                                                            layout: NSTextLayoutManager,
                                                                            model: EditorModel,
                                                                            window: NSWindow,
                                                                            sheet: NSView) {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container

        let textView = CodeWellTextView(frame: NSRect(x: 0, y: 0, width: width, height: height),
                                        textContainer: container)
        textView.theme = theme
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 28, height: 28)
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor(theme.ink)
        textView.insertionPointColor = NSColor(theme.primary)
        textView.drawsBackground = false                      // exactly as `makeNSView` sets it
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let model = EditorModel(text: markdown)
        model.hideMarkers = true       // Live + hide-markers: the mode that draws real checkboxes
        textView.string = model.text

        if let storage = textView.textStorage {
            EditorStyler(theme: theme).apply(to: storage, model: model)
        }
        // The coordinator's own wiring functions — not a re-implementation.
        textView.codeBlockRanges = EditorView.codeWellRanges(model)
        textView.taskCheckboxes = EditorView.taskCheckboxes(model)
        // The caret starts at offset 0, so the model's active block is the heading — its
        // current-line tint lands on the title, well clear of every sample below.
        textView.activeLineRange = EditorView.activeLineRange(model)

        let sheet = SheetView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        sheet.fill = theme.sheet
        sheet.addSubview(textView)

        // HOSTING IN A WINDOW IS REQUIRED, not a convenience: `drawTaskCheckboxes` culls cells
        // against `visibleRect`, and a view with no window has an EMPTY visibleRect — so a
        // window-less render silently draws no checkboxes at all (the wells and text still paint,
        // which makes the omission easy to miss). An offscreen borderless window gives the view a
        // real visible rect; it is never ordered front.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = sheet
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        textView.layoutSubtreeIfNeeded()
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        textView.layoutSubtreeIfNeeded()
        return (textView, layoutManager, model, window, sheet)
    }

    /// Stands in for the SwiftUI host's sheet background (the editor paints none of its own).
    final class SheetView: NSView {
        var fill: Color = .white
        /// Flipped so a sample point in text-view coordinates is the same point here (and the same
        /// bitmap row) — the text view is flipped, and it sits at this view's origin.
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor(fill).setFill()
            dirtyRect.fill()
        }
    }

    // MARK: - Rasterization

    struct Render {
        let rep: NSBitmapImageRep
        /// sRGB components at a point in VIEW coordinates (the text view is flipped, so view y and
        /// bitmap row agree).
        func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor? {
            rep.colorAt(x: Int(x.rounded()), y: Int(y.rounded()))?.usingColorSpace(.sRGB)
        }
        func png() -> Data? { rep.representation(using: .png, properties: [:]) }
    }

    /// Render the view under a named appearance.
    ///
    /// BOTH steps matter (see the suite doc): the per-view `appearance` fixes `effectiveAppearance`
    /// for code that resolves colors explicitly, and `performAsCurrentDrawingAppearance` makes the
    /// same appearance current for every dynamic `NSColor` resolved implicitly during `draw(_:)`.
    static func render(_ view: NSView, _ name: NSAppearance.Name) throws -> Render {
        let appearance = try #require(NSAppearance(named: name))
        view.window?.appearance = appearance
        view.appearance = appearance   // propagates to the text view (whose own `appearance` is nil)
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.subviews.forEach { $0.needsDisplay = true }
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        appearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        return Render(rep: rep)
    }

    // MARK: - Color helpers

    static func resolved(_ color: Color, _ name: NSAppearance.Name) -> NSColor {
        var out = NSColor.black
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            out = NSColor(color).usingColorSpace(.sRGB) ?? .black
        }
        return out
    }

    static func rgb(_ c: NSColor) -> (r: Double, g: Double, b: Double) {
        let s = c.usingColorSpace(.sRGB) ?? c
        return (s.redComponent, s.greenComponent, s.blueComponent)
    }

    static func distance(_ a: NSColor, _ b: NSColor) -> Double {
        let x = rgb(a), y = rgb(b)
        return ((x.r - y.r) * (x.r - y.r) + (x.g - y.g) * (x.g - y.g) + (x.b - y.b) * (x.b - y.b)).squareRoot()
    }

    static func luminance(_ c: NSColor) -> Double {
        let x = rgb(c)
        return 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b
    }

    static func describe(_ c: NSColor?) -> String {
        guard let x = c.map(rgb) else { return "nil" }
        return String(format: "#%02X%02X%02X", Int(x.r * 255), Int(x.g * 255), Int(x.b * 255))
    }

    /// The pixel in `rect` (view coordinates) CLOSEST to `target`, with its distance. Sampling a
    /// single "center" pixel of an antialiased SF Symbol is a coin flip; asking whether the region
    /// contains the expected color anywhere is the honest question.
    static func nearest(_ render: Render, in rect: CGRect, to target: NSColor) -> (color: NSColor?, distance: Double) {
        var best: NSColor?
        var bestDistance = Double.infinity
        for x in stride(from: rect.minX, through: rect.maxX, by: 1) {
            for y in stride(from: rect.minY, through: rect.maxY, by: 1) {
                guard let px = render.pixel(x, y) else { continue }
                let d = distance(px, target)
                if d < bestDistance { bestDistance = d; best = px }
            }
        }
        return (best, bestDistance)
    }

    /// The mean color over `rect` — used for the well, whose fill is a large flat area.
    static func mean(_ render: Render, in rect: CGRect) -> NSColor {
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for x in stride(from: rect.minX, through: rect.maxX, by: 1) {
            for y in stride(from: rect.minY, through: rect.maxY, by: 1) {
                guard let px = render.pixel(x, y) else { continue }
                let c = rgb(px)
                r += c.r; g += c.g; b += c.b; n += 1
            }
        }
        guard n > 0 else { return .black }
        return NSColor(srgbRed: r / n, green: g / n, blue: b / n, alpha: 1)
    }

    // MARK: - Geometry (the same seams the drawing code uses)

    /// The drawn well box for the fixture's fenced block, in VIEW coordinates.
    static func wellRect(_ view: CodeWellTextView, _ layout: NSTextLayoutManager) throws -> CGRect {
        let range = try #require(view.codeBlockRanges.first)
        let box = try #require(CodeWellGeometry.wellBox(for: range, in: layout))
        let origin = view.textContainerOrigin
        return box.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// The drawn checkbox rect for a task cell, in VIEW coordinates — mirrors
    /// `CodeWellTextView.drawTaskCheckboxes` (segment rect → centered square of side ≤ 14).
    static func checkboxRect(_ view: CodeWellTextView, _ layout: NSTextLayoutManager,
                             checked: Bool) throws -> CGRect {
        let box = try #require(view.taskCheckboxes.first { $0.checked == checked })
        let textRange = try #require(CodeWellGeometry.textRange(for: box.cell, in: layout))
        var union = CGRect.null
        layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            union = union.union(frame); return true
        }
        let cell = try #require(union.isNull ? nil : union)
        let origin = view.textContainerOrigin
        let side = min(14, max(cell.height - 2, 4))
        return CGRect(x: cell.midX + origin.x - side / 2, y: cell.midY + origin.y - side / 2,
                      width: side, height: side)
    }

    /// A patch of pure sheet: the top-left corner, inside the container inset and above all text.
    static let proseBackgroundRect = CGRect(x: 2, y: 2, width: 18, height: 18)

    // MARK: - PNG side-effect (best effort; never fails the test)

    static let pngDirectory = ProcessInfo.processInfo.environment["MARKER_RENDER_DUMP_DIR"]
        ?? "/private/tmp/claude-501/-Users-awizemann-Developer-Marker/10cd15f7-33cc-46c7-ad3b-74eae8a7ce8a/scratchpad"

    static func dump(_ render: Render, named name: String) {
        guard let data = render.png() else { return }
        let directory = URL(fileURLWithPath: pngDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(name))
    }

    // MARK: - The test

    @Test("The real editor renders light and dark differently at every themed sample")
    func renderedSamplesAdapt() throws {
        let light = Self.makeEditor()
        let dark = Self.makeEditor()   // a FRESH stack per appearance: no shared cached state can
                                       // leak a light render into the dark one (and vice versa).

        let lightRender = try Self.render(light.sheet, .aqua)
        let darkRender = try Self.render(dark.sheet, .darkAqua)
        Self.dump(lightRender, named: "light.png")
        Self.dump(darkRender, named: "dark.png")

        // --- 1. Sheet background behind prose -----------------------------------------------
        let lightSheet = Self.mean(lightRender, in: Self.proseBackgroundRect)
        let darkSheet = Self.mean(darkRender, in: Self.proseBackgroundRect)
        #expect(Self.distance(lightSheet, Self.resolved(Self.theme.sheet, .aqua)) < 0.03,
                "light sheet rendered \(Self.describe(lightSheet)), expected #FFFFFF")
        #expect(Self.distance(darkSheet, Self.resolved(Self.theme.sheet, .darkAqua)) < 0.03,
                "dark sheet rendered \(Self.describe(darkSheet)), expected #0C110E")
        #expect(Self.luminance(lightSheet) > 0.9, "light sheet is not light (\(Self.describe(lightSheet)))")
        #expect(Self.luminance(darkSheet) < 0.1, "dark sheet is not dark (\(Self.describe(darkSheet)))")
        #expect(Self.distance(lightSheet, darkSheet) > 0.5, "the sheet rendered the same in both appearances")

        // --- 2. The code well lifts off the sheet, in opposite directions --------------------
        // Sample the well's INTERIOR left gutter: inside the rounded box, left of the code glyphs and
        // clear of the 1px border, so it is the well fill over the sheet and nothing else.
        let lightWell = try Self.wellRect(light.view, light.layout).insetBy(dx: 6, dy: 6)
        let darkWell = try Self.wellRect(dark.view, dark.layout).insetBy(dx: 6, dy: 6)
        let lightWellPatch = CGRect(x: lightWell.minX, y: lightWell.minY, width: 6, height: lightWell.height)
        let darkWellPatch = CGRect(x: darkWell.minX, y: darkWell.minY, width: 6, height: darkWell.height)
        let lightWellColor = Self.mean(lightRender, in: lightWellPatch)
        let darkWellColor = Self.mean(darkRender, in: darkWellPatch)

        #expect(Self.luminance(lightWellColor) < Self.luminance(lightSheet) - 0.01,
                "light well (\(Self.describe(lightWellColor))) did not darken the sheet (\(Self.describe(lightSheet)))")
        #expect(Self.luminance(darkWellColor) > Self.luminance(darkSheet) + 0.01,
                "dark well (\(Self.describe(darkWellColor))) did not lift off the sheet (\(Self.describe(darkSheet)))")
        #expect(Self.distance(lightWellColor, darkWellColor) > 0.5, "the well rendered the same in both appearances")
        // The lift is SUBTLE by design (the token's alpha is 0.05) and stays neutral — a well that
        // came back saturated, or as strong as a solid fill, would be a regression just as much as one
        // that vanished. The exact composite is deliberately NOT asserted: AppKit blends into the
        // bitmap's own color space, so the rendered value is a few percent stronger than the naive
        // sRGB mix and over-fitting it would make the test brittle rather than truthful.
        for (label, sheetColor, rendered) in [("light", lightSheet, lightWellColor),
                                              ("dark", darkSheet, darkWellColor)] {
            let delta = abs(Self.luminance(rendered) - Self.luminance(sheetColor))
            #expect(delta > 0.02 && delta < 0.20,
                    "\(label) well lift off the sheet is \(delta) — expected a subtle band, got \(Self.describe(rendered))")
            let px = Self.rgb(rendered)
            let spread = max(px.r, max(px.g, px.b)) - min(px.r, min(px.g, px.b))
            #expect(spread < 0.05, "\(label) well is not near-neutral (\(Self.describe(rendered)))")
        }

        // --- 3. The CHECKED checkbox carries the primary green ------------------------------
        for (label, editor, render, appearance) in [
            ("light", light, lightRender, NSAppearance.Name.aqua),
            ("dark", dark, darkRender, NSAppearance.Name.darkAqua),
        ] {
            let rect = try Self.checkboxRect(editor.view, editor.layout, checked: true)
            let primary = Self.resolved(Self.theme.primary, appearance)
            let hit = Self.nearest(render, in: rect, to: primary)
            // A 14pt SF Symbol scaled from a 17×15 raster: even the purest fill pixel is an
            // antialiased blend of the accent with the sheet behind it, so the tolerance is loose.
            // The green-channel dominance assertions below are what actually pin the hue.
            #expect(hit.distance < 0.35,
                    "\(label) checked checkbox: closest pixel to primary was \(Self.describe(hit.color)) (d=\(hit.distance))")
            #expect(hit.distance < Self.distance(try #require(hit.color), Self.resolved(Self.theme.sheet, appearance)),
                    "\(label) checked checkbox: its best pixel is closer to the sheet than to the accent")
            let px = try #require(hit.color.map(Self.rgb))
            #expect(px.g > 0.45 && px.g > px.r + 0.2 && px.g > px.b + 0.2,
                    "\(label) checked checkbox fill is not green (\(Self.describe(hit.color)))")
            // The ✓ riding on the fill is the onAccent token, not the fill color. Asserted only when
            // onAccent is distinguishable from the sheet in this appearance — on LIGHT it is #FFFFFF,
            // the sheet color itself, so "some pixel in the box is white" would be vacuous. On dark
            // (#062012, a near-black green) it is a real claim.
            let onAccent = Self.resolved(Self.theme.onAccent, appearance)
            if Self.distance(onAccent, Self.resolved(Self.theme.sheet, appearance)) > 0.2 {
                let glyph = Self.nearest(render, in: rect, to: onAccent)
                #expect(glyph.distance < 0.12,
                        "\(label) checked checkbox: no onAccent ✓ pixel (closest \(Self.describe(glyph.color)))")
            }
        }
        // …and the two appearances differ.
        let lightChecked = try Self.checkboxRect(light.view, light.layout, checked: true)
        let darkChecked = try Self.checkboxRect(dark.view, dark.layout, checked: true)
        #expect(Self.distance(Self.mean(lightRender, in: lightChecked), Self.mean(darkRender, in: darkChecked)) > 0.05,
                "the checked checkbox rendered identically in both appearances")

        // --- 4. The UNCHECKED checkbox border is the neutral checkEmpty grey -----------------
        for (label, editor, render, appearance) in [
            ("light", light, lightRender, NSAppearance.Name.aqua),
            ("dark", dark, darkRender, NSAppearance.Name.darkAqua),
        ] {
            let rect = try Self.checkboxRect(editor.view, editor.layout, checked: false)
            let empty = Self.resolved(Self.theme.checkEmpty, appearance)
            let hit = Self.nearest(render, in: rect, to: empty)
            #expect(hit.distance < 0.10,
                    "\(label) unchecked checkbox: closest border pixel to checkEmpty was \(Self.describe(hit.color)) (d=\(hit.distance))")
            let px = try #require(hit.color.map(Self.rgb))
            let spread = max(px.r, max(px.g, px.b)) - min(px.r, min(px.g, px.b))
            #expect(spread < 0.10, "\(label) unchecked border is not a near-neutral grey (\(Self.describe(hit.color)))")
            // It must NOT be the accent — the empty box is unfilled.
            #expect(Self.distance(NSColor(srgbRed: px.r, green: px.g, blue: px.b, alpha: 1),
                                  Self.resolved(Self.theme.primary, appearance)) > 0.2,
                    "\(label) unchecked checkbox rendered the accent fill")
        }
        let lightEmpty = try Self.checkboxRect(light.view, light.layout, checked: false)
        let darkEmpty = try Self.checkboxRect(dark.view, dark.layout, checked: false)
        #expect(Self.distance(Self.mean(lightRender, in: lightEmpty), Self.mean(darkRender, in: darkEmpty)) > 0.05,
                "the unchecked checkbox rendered identically in both appearances")

        // --- 5. Whole-frame sanity: the renders are genuinely different images ---------------
        #expect(lightRender.png() != darkRender.png(), "the two appearance renders are byte-identical")
    }

    @Test("Prose ink renders as the theme's ink in each appearance")
    func proseInkRenders() throws {
        for (label, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let editor = Self.makeEditor()
            let render = try Self.render(editor.sheet, appearance)
            let paragraph = (Self.markdown as NSString).range(of: "A paragraph of prose")
            let textRange = try #require(CodeWellGeometry.textRange(for: paragraph, in: editor.layout))
            var union = CGRect.null
            editor.layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
                union = union.union(frame); return true
            }
            let origin = editor.view.textContainerOrigin
            let rect = union.offsetBy(dx: origin.x, dy: origin.y)
            let ink = Self.resolved(Self.theme.ink, appearance)
            let hit = Self.nearest(render, in: rect, to: ink)
            #expect(hit.distance < 0.10,
                    "\(label) prose ink: closest glyph pixel to the ink token was \(Self.describe(hit.color)) (d=\(hit.distance))")
        }
    }
}
