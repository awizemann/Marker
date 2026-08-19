import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Marker

/// An `NSTextView` that draws a rounded, bordered "well" behind each fenced code block, and floats a
/// hover-reveal **copy button** in each block's top-right corner. A grey `.backgroundColor` attribute
/// can only paint a flat rectangle, and the code must stay LIVE + editable (so no `NSTextAttachment`
/// like the grid tables) — so we draw the box ourselves behind the text, and the copy button is a
/// single real `NSButton` subview that snaps to whichever code block the mouse is over (it scrolls
/// glued to content, being a subview of the document view). Bytes are never touched.
final class CodeWellTextView: NSTextView {

    /// The design tokens the well/tint/copy-button colors resolve through. Defaults to the pre-wiring
    /// `MarkerTheme.fallback`; the host (EditorView) sets the real theme in `makeNSView`.
    var theme: MarkerTheme = MarkerTheme.fallback

    // MARK: - Drag-and-drop images

    /// Images dropped onto the editor, each with a security-scoped bookmark minted synchronously here
    /// (while the drop grant is live). Handed to the host → AppStore, which persists + inserts them.
    /// Set by the host in `makeNSView`.
    var onDropImages: (([CapturedImageDrop]) -> Void)?

    /// NON-image file URLs dropped onto the editor, called synchronously inside
    /// `performDragOperation` (while the drop's sandbox grant is still live — a sandboxed consumer
    /// that needs the URLs later must mint bookmarks inside this call, like the image path does).
    /// Set by the host in `makeNSView`; returns `true` when the drop was consumed (the consumer
    /// produced markdown that was inserted), `false` to fall through to NSTextView's default
    /// handling. nil (the default) keeps the pre-seam behavior byte-identical: only image drops
    /// are intercepted, everything else goes to `super`.
    var onDropFiles: (([URL]) -> Bool)?

    /// PLAIN-STRING drops (a dragged list row, a dragged text snippet): the string is offered to
    /// the host BEFORE NSTextView's default string insertion — but only when the seam is wired AND
    /// the drag carries no file URLs (file/image drops keep their own paths above; a file drag
    /// often ALSO writes its path as a string, which must not double-handle). Returns `true` when
    /// consumed (the consumer produced markdown that was inserted); `false` falls through to the
    /// default insertion, so an ordinary text drag still lands as text. nil (the default) keeps
    /// the pre-seam behavior byte-identical. Set by the host in `makeNSView`.
    var onDropText: ((String) -> Bool)?

    /// FIRST-RESPONDER tracking, set by the host in `makeNSView`: reports keyboard focus entering/
    /// leaving the editor (become/resignFirstResponder) so the model's `isFocused` stays truthful
    /// and consumers can gate focus-sensitive commands (menu key equivalents) on real focus.
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    /// Pre-mouseDown seam, set by the host in `makeNSView`: called with the clicked character index
    /// (insertion-point space) and whether ⌘ was held. Return `true` to CONSUME the click (checkbox
    /// toggle, Cmd+click link activation); `false` falls through to NSTextView's normal caret placement.
    var onMouseDown: ((_ characterIndex: Int, _ commandHeld: Bool) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        if let onMouseDown {
            let point = convert(event.locationInWindow, from: nil)
            let index = characterIndexForInsertion(at: point)
            if onMouseDown(index, event.modifierFlags.contains(.command)) { return }
        }
        super.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if !imageURLs(from: sender).isEmpty { return .copy }
        // Only when the generalized seam is wired: accept non-image file drags too. With no
        // consumer (TrapperKeeper today) this branch is dead and the behavior is exactly pre-seam.
        if onDropFiles != nil, !fileURLs(from: sender).isEmpty { return .copy }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // IMAGE drops keep their existing path, unchanged and FIRST (consumers that only wire
        // `onDropImages` — TrapperKeeper — must behave byte-identically). Mint each dropped image's
        // bookmark HERE, synchronously, while the drop's sandbox grant is guaranteed live — the
        // async insert that follows cannot rely on that transient grant.
        let images = imageURLs(from: sender)
        let drops: [CapturedImageDrop] = images.compactMap { url in
            let holding = url.startAccessingSecurityScopedResource()
            defer { if holding { url.stopAccessingSecurityScopedResource() } }
            guard let blob = try? url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
            return CapturedImageDrop(url: url, bookmark: blob)
        }
        if !drops.isEmpty {
            // Place the caret nearest the drop point so the reference lands where dropped, then hand off.
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil)), length: 0))
            onDropImages?(drops)
            // MIXED drop (images + other files): the images take their path above; the REMAINING
            // non-image URLs go to the seam, at the same drop caret. The image insert is async
            // (consumer-side), the seam insert synchronous — so links land at the drop point first
            // and image references follow after them, both where the user dropped.
            if onDropFiles != nil {
                let imageSet = Set(images)
                let others = fileURLs(from: sender).filter { !imageSet.contains($0) }
                if !others.isEmpty { _ = onDropFiles?(others) }
            }
            return true
        }
        // NON-image file drop → the generalized seam. Called synchronously (drop grant live); the
        // consumer returning nil / the seam being unwired falls through to the default handling.
        if onDropFiles != nil {
            let files = fileURLs(from: sender)
            if !files.isEmpty {
                setSelectedRange(NSRange(location: characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil)), length: 0))
                if onDropFiles?(files) == true { return true }
            }
        }
        // PLAIN-STRING drop → the text seam (gated by the pure `plainTextDrop`: never when the drag
        // carries file URLs — those keep the paths above). Caret placed at the drop point first, so
        // the consumer's markdown AND the fall-through default insertion both land where dropped.
        if onDropText != nil,
           let string = EditorCommands.plainTextDrop(hasFileURLs: !fileURLs(from: sender).isEmpty,
                                                     pasteboardString: sender.draggingPasteboard.string(forType: .string)) {
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil)), length: 0))
            if onDropText?(string) == true { return true }
        }
        return super.performDragOperation(sender)   // non-file / mint failed / consumer declined → default
    }

    /// The dropped file URLs that are images (by content type); [] when the drop isn't image files.
    private func imageURLs(from sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        return (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    /// ALL dropped file URLs, any content type; [] when the drop carries no file URLs.
    private func fileURLs(from sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    /// Absolute UTF-16 ranges of the code blocks to box, in Live mode (empty in Source mode). Set by
    /// the coordinator after each parse/restyle; a change hides the (now possibly stale) copy button.
    var codeBlockRanges: [NSRange] = [] {
        didSet {
            guard codeBlockRanges != oldValue else { return }
            hideCopyButton()
            needsDisplay = true
        }
    }

    /// The caret's block range — painted with a soft current-line tint drawn BEHIND the text (never a
    /// `.backgroundColor` attribute). Keeping it out of the storage is what makes a caret move do zero
    /// text-storage edits: no `beginEditing`, so no TextKit-2 layout invalidation, so a click on a long
    /// document can't collapse the frame height and clamp the scroll toward the top (t-6cfaf799).
    var activeLineRange: NSRange? {
        didSet {
            guard activeLineRange != oldValue else { return }
            needsDisplay = true
        }
    }

    /// A task item's `[ ]`/`[x]` cell: the 3-character span (whose glyphs styling paints CLEAR in
    /// hide-markers mode) and its checked state. The checkbox symbol is drawn over that span.
    struct TaskCheckbox: Equatable {
        var cell: NSRange
        var checked: Bool
    }

    /// The task checkboxes to paint, in Live + hide-markers mode only (empty otherwise — Source mode
    /// and marker-visible mode show the literal `- [x]` text). Set by the coordinator after each
    /// parse/restyle, exactly like `codeBlockRanges`.
    var taskCheckboxes: [TaskCheckbox] = [] {
        didSet {
            guard taskCheckboxes != oldValue else { return }
            needsDisplay = true
        }
    }

    // MARK: Drawing (the boxed well, behind the text)

    /// Custom drawing (wells, current-line tint, checkboxes) resolves theme colors at draw time and
    /// bakes the checkbox tint into a cached image, so an appearance flip must repaint. NSTextView
    /// redraws its own attributed-string colors (they stay dynamic `NSColor`s), and the copy button's
    /// `contentTintColor` holds the dynamic color live, but nothing guarantees a full invalidation for
    /// OUR drawn layers — ask for one explicitly.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCodeWells()      // behind the text…
        drawActiveLine()     // …the current-line tint over the well but behind glyphs…
        drawTaskCheckboxes() // …the checkbox symbols above the tint (the cell's own glyphs are clear)…
        super.draw(dirtyRect) // …then the glyphs (and selection/caret) on top
    }

    /// Paint the soft current-line band behind the caret's block. Uses the already-laid-out fragment
    /// geometry (no `ensureLayout`), so it only draws when the active block is within laid-out content.
    private func drawActiveLine() {
        guard let range = activeLineRange, range.length > 0,
              let layoutManager = textLayoutManager,
              let rect = fragmentUnion(for: range, in: layoutManager) else { return }
        let origin = textContainerOrigin
        // A code block's LAYOUT fragment union carries the well's outer paragraph spacing — measure
        // the tint off the line fragments instead, so it lands on the well's glyph area rather than
        // bleeding into the gap above/below. Non-code blocks keep the plain fragment union.
        let vertical = codeBlockRanges.contains(range)
            ? (CodeWellGeometry.wellBox(for: range, in: layoutManager) ?? rect)
            : rect
        let box = CGRect(x: rect.minX + origin.x, y: vertical.minY + origin.y, width: rect.width, height: vertical.height)
        // Soft current-line indicator (== EditorStyler's former `currentLineTint`).
        NSColor(theme.activeLineTint).setFill()
        NSBezierPath(rect: box).fill()
    }

    /// Paint an SF Symbol checkbox over each task item's `[ ]`/`[x]` cell. The cell characters stay in
    /// storage at full width (styling only paints them clear), so the symbol lands exactly on the click
    /// target `EditorCommands.taskCheckboxToggle` uses — bytes and caret offsets are untouched.
    /// Only already-laid-out cells draw (`segmentRect` enumerates existing layout only): no forced
    /// full-document layout. Cells outside the viewport are culled before any symbol work.
    private func drawTaskCheckboxes() {
        guard !taskCheckboxes.isEmpty, let layoutManager = textLayoutManager else { return }
        let origin = textContainerOrigin
        // The viewport in CONTAINER coordinates — `segmentRect` returns container-space rects.
        let viewport = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        for box in taskCheckboxes {
            guard box.cell.length > 0,
                  let cell = segmentRect(for: box.cell, in: layoutManager),
                  cell.intersects(viewport) else { continue }
            // Center on the CELL's own segment rect (its line), not the paragraph's fragment union —
            // a wrapped task item spans several lines and the checkbox belongs on the first.
            let side = min(Self.checkboxPointSize, max(cell.height - 2, 4))
            let rect = CGRect(x: cell.midX + origin.x - side / 2,
                              y: cell.midY + origin.y - side / 2,
                              width: side, height: side)
            // Checked = ✓ (onAccent) on a square FILLED with the primary accent; empty = an
            // unfilled square stroked in checkEmpty. Palette order is glyph-first, then fill.
            let palette: [NSColor] = box.checked
                ? [NSColor(theme.onAccent), NSColor(theme.primary)]
                : [NSColor(theme.checkEmpty)]
            guard let image = Self.checkboxImage(checked: box.checked, palette: palette, side: side,
                                                 appearance: effectiveAppearance) else { continue }
            image.draw(in: rect)
        }
    }

    /// The typographic segment rect for `nsRange` (container coordinates) — the cell's horizontal
    /// extent, which the line-fragment union alone can't give. Enumerates EXISTING layout only (no
    /// `.ensuresLayout`), so a cell that isn't laid out yet simply returns nil and draws nothing.
    private func segmentRect(for nsRange: NSRange, in layoutManager: NSTextLayoutManager) -> CGRect? {
        guard let textRange = CodeWellGeometry.textRange(for: nsRange, in: layoutManager) else { return nil }
        var union = CGRect.null
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            union = union.union(frame)
            return true
        }
        return union.isNull ? nil : union
    }

    /// ~the body font's cap area — the checkbox reads as a control, not a glyph.
    private static let checkboxPointSize: CGFloat = 14

    /// A palette-tinted SF Symbol for the cell. Cached per (checked, RESOLVED palette, size) so a
    /// scroll doesn't re-render symbol images on every frame.
    ///
    /// The key is the palette RESOLVED under the view's appearance, not the color objects: the tints
    /// are BAKED into the image at render time, so a dynamic theme color (whose `description` is a
    /// per-instance UUID, identical in both appearances and fresh on every `adaptive` call) would both
    /// serve a light checkbox back after a flip to dark AND grow the cache without bound for a
    /// consumer that rebuilds its theme each render. Resolved components have neither problem.
    private static var checkboxImageCache: [String: NSImage] = [:]

    /// Internal (not private) so tests can render the two states and compare them.
    static func checkboxImage(checked: Bool, palette: [NSColor], side: CGFloat,
                                      appearance: NSAppearance) -> NSImage? {
        // Resolve the (possibly dynamic) tints under the VIEW's appearance — not whatever drawing
        // appearance happens to be current when this first runs — and key the cache on the result.
        var resolved = palette
        appearance.performAsCurrentDrawingAppearance {
            resolved = palette.map { $0.usingColorSpace(.sRGB) ?? $0 }
        }
        // The appearance name rides along too: if a tint can't be resolved to sRGB (pattern/catalog
        // oddities) the fallback description is per-instance, and the name keeps light/dark apart.
        let key = "\(checked)|\(appearance.name.rawValue)|\(resolved.map(\.description).joined(separator: ","))|\(Int(side.rounded()))"
        if let cached = checkboxImageCache[key] { return cached }
        let name = checked ? "checkmark.square.fill" : "square"
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: checked ? "Checked" : "Unchecked") else { return nil }
        // The empty square is a hairline at this size; .medium approximates the design's 1.5px stroke.
        let config = NSImage.SymbolConfiguration(pointSize: side, weight: checked ? .regular : .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: resolved))
        let image = symbol.withSymbolConfiguration(config) ?? symbol
        // The system symbol arrives as a TEMPLATE image, which `draw(in:)` would repaint with the
        // current fill color and throw the palette tint away. Opt out so the tint survives.
        image.isTemplate = false
        checkboxImageCache[key] = image
        return image
    }

    private func drawCodeWells() {
        let fill = NSColor(theme.well)
        let border = NSColor(theme.line)
        for (_, box) in codeBoxes() {
            let path = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
            fill.setFill(); path.fill()
            border.setStroke(); path.lineWidth = 1; path.stroke()
        }
    }

    /// The (range, box-rect) for every code block that's currently laid out. Shared by drawing and by
    /// hover hit-testing so the box and the copy button always agree on geometry.
    private func codeBoxes() -> [(range: NSRange, box: CGRect)] {
        guard !codeBlockRanges.isEmpty, let layoutManager = textLayoutManager, let container = textContainer else { return [] }
        let origin = textContainerOrigin
        let padding = container.lineFragmentPadding
        let column = container.size.width - 2 * padding
        guard column > 0 else { return [] }
        let hInset = CodeWellMetrics.horizontalInset       // box breathes past the text on each side
        let left = origin.x + padding - hInset
        let width = column + 2 * hInset

        var result: [(NSRange, CGRect)] = []
        for range in codeBlockRanges {
            guard let box = CodeWellGeometry.wellBox(for: range, in: layoutManager) else { continue }
            result.append((range, NSRect(x: left, y: box.minY + origin.y, width: width, height: box.height)))
        }
        return result
    }

    /// Union of the layout-fragment frames covering `nsRange` (container coordinates), or nil if the
    /// range doesn't resolve / isn't laid out. No `.ensuresLayout`: we only decorate already-laid-out
    /// (≈ visible) content, so we never force full-document layout on every draw or scroll.
    private func fragmentUnion(for nsRange: NSRange, in layoutManager: NSTextLayoutManager) -> CGRect? {
        guard let textRange = CodeWellGeometry.textRange(for: nsRange, in: layoutManager) else { return nil }
        var union = CGRect.null
        layoutManager.enumerateTextLayoutFragments(from: textRange.location, options: []) { fragment in
            guard fragment.rangeInElement.location.compare(textRange.endLocation) == .orderedAscending else { return false }
            union = union.union(fragment.layoutFragmentFrame)
            return true
        }
        return union.isNull ? nil : union
    }

    // MARK: Copy button (one hover-reveal NSButton that follows the mouse)

    private var copyButton: NSButton?
    /// The code block the visible copy button will copy — the one the mouse is currently over.
    private var copyTargetRange: NSRange?
    /// That block's box rect (view coords), kept so the button can stay sticky as the view scrolls.
    private var copyTargetBox: CGRect?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea { removeTrackingArea(existing) }   // remove only OURS, not NSTextView's
        let area = NSTrackingArea(rect: .zero,
                                  options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if let hit = codeBoxes().first(where: { $0.box.contains(point) }) {
            showCopyButton(for: hit.range, box: hit.box)
        } else {
            hideCopyButton()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideCopyButton()
    }

    private func showCopyButton(for range: NSRange, box: CGRect) {
        let button = copyButtonView()
        copyTargetRange = range
        copyTargetBox = box
        positionCopyButton(box)
        if button.isHidden { button.isHidden = false }
    }

    /// Place the button at the box's top-right, STICKY: pinned to the box top, but clamped to stay
    /// within the visible viewport and never below the box — so a tall code block scrolled partway
    /// off-screen still shows a reachable copy button (Alan: "never goes outside the code box").
    private func positionCopyButton(_ box: CGRect) {
        guard let button = copyButton else { return }
        let size = NSSize(width: 26, height: 20)
        let x = box.maxX - size.width - 8
        let top = max(box.minY + 6, visibleRect.minY + 6)
        let y = min(top, box.maxY - size.height - 6)
        button.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func hideCopyButton() {
        copyButton?.isHidden = true
        copyTargetRange = nil
        copyTargetBox = nil
    }

    // MARK: Keep the button reachable while scrolling

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportDidScroll),
                                               name: NSView.boundsDidChangeNotification, object: clip)
    }

    @objc private func viewportDidScroll() {
        guard let box = copyTargetBox, copyButton?.isHidden == false else { return }
        // The block scrolled fully out of view → hide; otherwise keep the button sticky in the viewport.
        if box.maxY <= visibleRect.minY || box.minY >= visibleRect.maxY {
            hideCopyButton()
        } else {
            positionCopyButton(box)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func copyButtonView() -> NSButton {
        if let button = copyButton { return button }
        let button = NSButton()
        button.bezelStyle = .roundRect
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = Self.copyIcon
        button.contentTintColor = NSColor(theme.muted)
        button.target = self
        button.action = #selector(copyHoveredBlock)
        button.toolTip = "Copy code"
        button.setAccessibilityLabel("Copy code block")
        button.isHidden = true
        addSubview(button)
        copyButton = button
        return button
    }

    @objc private func copyHoveredBlock() {
        guard let range = copyTargetRange,
              range.length > 0, NSMaxRange(range) <= (string as NSString).length,
              let code = MarkdownCodeBlock.codeText(inBlockText: (string as NSString).substring(with: range))
        else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        flashCopied()
    }

    /// Momentary confirmation: swap to a green checkmark, then revert.
    private func flashCopied() {
        guard let button = copyButton else { return }
        button.image = Self.copiedIcon
        button.contentTintColor = NSColor(theme.primary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, let button = self.copyButton else { return }
            button.image = Self.copyIcon
            button.contentTintColor = NSColor(self.theme.muted)
        }
    }

    private static let copyIcon = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy code")
    private static let copiedIcon = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
}

/// The code well's DRAWN geometry, kept out of the view so it can be exercised against a bare
/// TextKit 2 stack in tests.
///
/// The box is measured from the block's **text line fragments** — never from `layoutFragmentFrame`,
/// which folds in the `paragraphSpacingBefore`/`paragraphSpacing` `EditorStyler` puts on the block's
/// outer lines. Subtracting those numbers back out looks equivalent but is not: TextKit 2 does NOT
/// apply `paragraphSpacing` to a final paragraph that has no trailing newline, so a code block at
/// EOF would have had 10pt subtracted that was never added — cutting the box into the closing fence
/// — and an unterminated fence at EOF would have produced an overly tall frame. The line fragments
/// carry only the glyph lines, so the union is exact in every case; `interiorPadding` is the only
/// air added back.
nonisolated enum CodeWellGeometry {

    /// The drawn box for a laid-out line-fragment union: the glyph area plus interior padding above
    /// and below. Pure — the whole vertical contract lives here.
    static func box(forLineFragmentUnion rect: CGRect) -> CGRect {
        rect.insetBy(dx: 0, dy: -CodeWellMetrics.interiorPadding)
    }

    /// The union of the TEXT LINE FRAGMENTS covering `nsRange`, in container coordinates, or nil when
    /// the range doesn't resolve / isn't laid out. No `.ensuresLayout`: only already-laid-out
    /// (≈ visible) content is decorated, so drawing never forces full-document layout.
    static func lineFragmentUnion(for nsRange: NSRange, in layoutManager: NSTextLayoutManager) -> CGRect? {
        guard let textRange = textRange(for: nsRange, in: layoutManager) else { return nil }
        var union = CGRect.null
        layoutManager.enumerateTextLayoutFragments(from: textRange.location, options: []) { fragment in
            guard fragment.rangeInElement.location.compare(textRange.endLocation) == .orderedAscending else { return false }
            let origin = fragment.layoutFragmentFrame.origin
            for line in fragment.textLineFragments {
                union = union.union(line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y))
            }
            return true
        }
        return union.isNull ? nil : union
    }

    /// The well box for a code block's character range, or nil when it isn't laid out.
    static func wellBox(for nsRange: NSRange, in layoutManager: NSTextLayoutManager) -> CGRect? {
        lineFragmentUnion(for: nsRange, in: layoutManager).map(box(forLineFragmentUnion:))
    }

    /// `nsRange` (UTF-16, document-relative) resolved against the layout manager's content.
    static func textRange(for nsRange: NSRange, in layoutManager: NSTextLayoutManager) -> NSTextRange? {
        guard let content = layoutManager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: nsRange.location),
              let end = content.location(start, offsetBy: nsRange.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }
}
