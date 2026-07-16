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

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        imageURLs(from: sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // Mint each dropped image's bookmark HERE, synchronously, while the drop's sandbox grant is
        // guaranteed live — the async insert that follows cannot rely on that transient grant.
        let drops: [CapturedImageDrop] = imageURLs(from: sender).compactMap { url in
            let holding = url.startAccessingSecurityScopedResource()
            defer { if holding { url.stopAccessingSecurityScopedResource() } }
            guard let blob = try? url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
            return CapturedImageDrop(url: url, bookmark: blob)
        }
        guard !drops.isEmpty else { return super.performDragOperation(sender) }   // non-image / mint failed → default
        // Place the caret nearest the drop point so the reference lands where dropped, then hand off.
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil)), length: 0))
        onDropImages?(drops)
        return true
    }

    /// The dropped file URLs that are images (by content type); [] when the drop isn't image files.
    private func imageURLs(from sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
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

    // MARK: Drawing (the boxed well, behind the text)

    override func draw(_ dirtyRect: NSRect) {
        drawCodeWells()      // behind the text…
        drawActiveLine()     // …the current-line tint over the well but behind glyphs…
        super.draw(dirtyRect) // …then the glyphs (and selection/caret) on top
    }

    /// Paint the soft current-line band behind the caret's block. Uses the already-laid-out fragment
    /// geometry (no `ensureLayout`), so it only draws when the active block is within laid-out content.
    private func drawActiveLine() {
        guard let range = activeLineRange, range.length > 0,
              let layoutManager = textLayoutManager,
              let rect = fragmentUnion(for: range, in: layoutManager) else { return }
        let origin = textContainerOrigin
        let box = CGRect(x: rect.minX + origin.x, y: rect.minY + origin.y, width: rect.width, height: rect.height)
        // Soft current-line indicator (== EditorStyler's former `currentLineTint`).
        NSColor(theme.activeLineTint).setFill()
        NSBezierPath(rect: box).fill()
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
        let hInset: CGFloat = 8                            // box breathes past the text on each side
        let left = origin.x + padding - hInset
        let width = column + 2 * hInset

        var result: [(NSRange, CGRect)] = []
        for range in codeBlockRanges {
            guard let rect = fragmentUnion(for: range, in: layoutManager) else { continue }
            result.append((range, NSRect(x: left, y: rect.minY + origin.y - 4, width: width, height: rect.height + 8)))
        }
        return result
    }

    /// Union of the layout-fragment frames covering `nsRange` (container coordinates), or nil if the
    /// range doesn't resolve / isn't laid out. No `.ensuresLayout`: we only decorate already-laid-out
    /// (≈ visible) content, so we never force full-document layout on every draw or scroll.
    private func fragmentUnion(for nsRange: NSRange, in layoutManager: NSTextLayoutManager) -> CGRect? {
        guard let content = layoutManager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: nsRange.location),
              let end = content.location(start, offsetBy: nsRange.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }
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
