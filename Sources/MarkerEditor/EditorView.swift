import SwiftUI
import AppKit
import Marker

/// What a Cmd+click in the editor activated: a URL (from `[text](url)`, `<url>`, or a bare URL) or
/// a wiki-link target (the text inside `[[…]]`). The consumer resolves/open its own way — the editor
/// never opens anything itself.
public enum MarkerLinkTarget: Sendable {
    case url(String)
    case wiki(String)
}

/// Hosts a native **TextKit 2** NSTextView for one markdown document. The text storage IS the raw
/// markdown (canonical); editing pushes the new string + caret back into the EditorModel, which
/// reparses. Block styling (WYSIWYG + the cursor-line source reveal) is applied in P1.3 — here the
/// host just renders the raw text and keeps the model in sync.
public struct EditorView: NSViewRepresentable {
    @Bindable var model: EditorModel
    /// The design tokens the editor renders with (built by the consumer from its design system).
    let theme: MarkerTheme
    /// Optional code-fence token provider (MarkerHighlighting's `CodeHighlighter`); nil → code
    /// fences keep their flat mono style.
    let highlighter: (any CodeTokenProviding)?
    /// Called when the user **Cmd+clicks** a link (`[text](url)` / `<url>` / bare URL) or a
    /// `[[wiki link]]` in Live mode. Cmd+click is the editor convention: a PLAIN click must keep its
    /// editing ergonomics (it just places the caret, even inside a link), so activation requires the
    /// modifier. nil → links render styled but aren't clickable.
    public var onLinkActivate: ((MarkerLinkTarget) -> Void)?

    public init(model: EditorModel, theme: MarkerTheme, highlighter: (any CodeTokenProviding)? = nil,
                onLinkActivate: ((MarkerLinkTarget) -> Void)? = nil) {
        self.model = model
        self.theme = theme
        self.highlighter = highlighter
        self.onLinkActivate = onLinkActivate
    }

    var styler: EditorStyler { EditorStyler(theme: theme, highlighter: highlighter) }

    public func makeNSView(context: Context) -> NSScrollView {
        // Explicit TextKit 2 stack (content storage + layout manager + container).
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container

        // Grid tables: substitute the raw pipes of inactive `.table` blocks with a grid attachment at
        // DISPLAY time (bytes untouched). Set before the first `string` assignment so initial tables
        // render as grids. The content storage holds the delegate weakly — the coordinator retains it.
        let tableDelegate = TableContentDelegate(model: model, theme: theme)
        contentStorage.delegate = tableDelegate
        context.coordinator.tableDelegate = tableDelegate

        let textView = CodeWellTextView(frame: .zero, textContainer: container)
        textView.theme = theme
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 28, height: 28)
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor(theme.ink)
        textView.insertionPointColor = NSColor(theme.primary)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        // Let the text view grow its frame to the FULL document height. Without an unbounded maxSize,
        // `isVerticallyResizable` clamps the frame to the text view's DEFAULT maxSize (≈ the initial
        // viewport height), so a tall document can't be scrolled — content below the first screenful is
        // unreachable, and only a window-resize layout pass ever bumps the frame. This is the canonical
        // NSTextView-in-NSScrollView recipe (min 0, max unbounded); the container height is already
        // unbounded and `widthTracksTextView` keeps the width wrapping to the view.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = model.text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        context.coordinator.textView = textView
        // Drag-and-drop images: register the file-URL type and route image drops to the model → AppStore
        // (which mints access + inserts). Non-image drops fall through to NSTextView's default handling.
        textView.registerForDraggedTypes([.fileURL])
        let editorModel = model
        textView.onDropImages = { [weak editorModel] drops in editorModel?.onDropImages?(drops) }
        // Wire the ⌘K mutation seam: the coordinator is the only thing that can apply an undo-registered
        // edit + read the caret rect. The model holds it weakly (see EditorTextMutating).
        model.mutator = context.coordinator
        // Click interception (checkbox toggles on plain click, Cmd+click link activation): the text
        // view asks the coordinator BEFORE default mouseDown handling; `true` consumes the click.
        context.coordinator.onLinkActivate = onLinkActivate
        textView.onMouseDown = { [weak coordinator = context.coordinator] index, commandHeld in
            coordinator?.handleMouseDown(at: index, commandHeld: commandHeld) ?? false
        }
        EditorScrollTrace.install(scrollView: scrollView)   // no-op unless TK_SCROLL_TRACE=1
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.styler = styler   // keep keystroke restyles on the CURRENT theme/highlighter
        coordinator.onLinkActivate = onLinkActivate   // closures aren't comparable; just keep it fresh
        // Read-only lock (trial expired / license revoked): the text view stays SELECTABLE (read,
        // scroll, copy all live) but not EDITABLE, so typing/paste/delete are refused natively. Read
        // `model.isReadOnly` here so a lock flip re-invokes this method; set it BEFORE the restyle
        // early-return below (a lock change touches no styling).
        let editable = !model.isReadOnly
        if textView.isEditable != editable { textView.isEditable = editable }
        // Sync only when the model's text changed OUT from under the view (opening / closing a
        // document via `editor.load`). Never overwrite during an in-progress edit (strings match then).
        // We swap the string in place rather than `.id()`-resetting the host (see view discipline);
        // a swap means a NEW document, so reset undo + caret + scroll so they don't bleed across files.
        let textChanged = textView.string != model.text
        if textChanged {
            textView.string = model.text
            textView.undoManager?.removeAllActions()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scroll(.zero)
        }
        // A FULL restyle here is warranted ONLY when the text was swapped from the model side (doc
        // open/close / external reload — `textChanged`) or a style mode changed (Live↔Source,
        // hide-markers, indent-headings). In-editor edits are restyled by the delegate (`textDidChange`,
        // block-incremental); caret/selection moves touch NO storage — they just move the current-line
        // overlay. Reading ONLY these inputs here (never `activeBlock`/`selection`) is what stops a click
        // from making Observation re-invoke `updateNSView` → a full-document relayout that, on a long
        // document, snaps the scroll back toward the top (the "editor jumps when you edit" bug, t-6cfaf799).
        let modes = StyleModes(source: model.isSourceMode, hideMarkers: model.hideMarkers, indentHeaders: model.indentHeaders)
        guard textChanged || coordinator.styleModes != modes else { return }
        coordinator.styleModes = modes
        EditorScrollTrace.mark("updateNSView FULL apply (textChanged=\(textChanged))")
        // Re-apply block styling (covers initial layout, the Live/Source toggle, marker toggles, and
        // external changes).
        if let storage = textView.textStorage {
            styler.apply(to: storage, model: model)
        }
        if let codeWell = textView as? CodeWellTextView {
            codeWell.codeBlockRanges = Self.codeWellRanges(model)
            codeWell.activeLineRange = Self.activeLineRange(model)
        }
    }

    /// The caret's block range for the current-line overlay (nil in Source mode, which has no band).
    static func activeLineRange(_ model: EditorModel) -> NSRange? {
        guard !model.isSourceMode, let block = model.activeBlock, block.range.length > 0 else { return nil }
        return block.range
    }

    /// The code blocks to draw a boxed well behind — only in Live mode (Source shows raw mono, no well).
    static func codeWellRanges(_ model: EditorModel) -> [NSRange] {
        guard !model.isSourceMode else { return [] }
        return model.document.blocks.compactMap { block in
            if case .codeBlock = block.kind { return block.range }
            return nil
        }
    }

    /// The non-text style inputs that warrant a full restyle. Compared in `updateNSView` so a caret
    /// move (which changes none of them) never triggers the full pass — only a real mode toggle does.
    struct StyleModes: Equatable {
        var source: Bool
        var hideMarkers: Bool
        var indentHeaders: Bool
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(model: model, styler: EditorStyler(theme: theme, highlighter: highlighter))
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        let model: EditorModel
        /// The theme-bound styler (mirrors the host's; the coordinator restyles on text/selection
        /// changes where it has no access to the representable value). `var`: updateNSView refreshes
        /// it each pass so a consumer-changed theme/highlighter reaches keystroke restyles too —
        /// makeCoordinator runs once, so a frozen copy would go stale (cold-audit observation).
        var styler: EditorStyler
        weak var textView: NSTextView?
        /// The grid-table content-storage delegate (retained here; the content storage holds it weakly).
        var tableDelegate: TableContentDelegate?
        /// The style inputs the storage was last FULLY styled for; `updateNSView` re-runs the full pass
        /// only when these change (or the text is swapped) — never on a caret move (see t-6cfaf799).
        var styleModes: EditorView.StyleModes?
        /// The consumer's link-activation callback (Cmd+click on a link / wiki link). Kept on the
        /// coordinator (refreshed each `updateNSView`) so the text view's mouseDown seam reaches it.
        var onLinkActivate: ((MarkerLinkTarget) -> Void)?

        init(model: EditorModel, styler: EditorStyler) {
            self.model = model
            self.styler = styler
        }

        /// Caret point (window top-left space) cached on every caret move WHILE the text view is first
        /// responder — so ⌘K can anchor at the caret even though opening the palette moves focus to its
        /// search field (at which point a fresh `firstRect` would be stale/zero).
        private var cachedCaretPoint: CGPoint?

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Read-only lock safety net: `isEditable = false` normally stops native edits before they
            // fire this, but it's set asynchronously in `updateNSView`, so a keystroke in-flight during
            // the render tick that flips the lock (a mid-session revocation) could still land one edit.
            // Refuse it here so the model never adopts a mutation made while locked; the next
            // `updateNSView` reverts the stray character from the text view.
            guard !model.isReadOnly else { return }
            EditorScrollTrace.mark("textDidChange sel=\(NSStringFromRange(textView.selectedRange()))")
            let previousBlocks = model.document.blocks
            model.updateText(textView.string, selection: textView.selectedRange())
            cachedCaretPoint = computeCaretPoint(textView)
            // Restyle ONLY the blocks the edit changed, not the whole document — a full restyle re-sets
            // attributes over the entire storage, collapsing TextKit-2's laid-out height so a long doc's
            // scroll snaps toward the top when you type (t-6cfaf799; see EditorStyler.restyleTextChange).
            if let storage = textView.textStorage {
                styler.restyleTextChange(in: storage, model: model, previousBlocks: previousBlocks)
            }
            if let codeWell = textView as? CodeWellTextView {
                codeWell.codeBlockRanges = EditorView.codeWellRanges(model)
                codeWell.activeLineRange = EditorView.activeLineRange(model)
            }
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let previousActive = model.activeBlockID
            model.updateSelection(textView.selectedRange())
            cachedCaretPoint = computeCaretPoint(textView)
            // A caret move touches NO text storage — every block renders identically active-or-not (the
            // "retire cursor-line reveal" decision), so the ONLY thing that moves is the soft current-line
            // band, which CodeWellTextView draws as an overlay. Setting a range (vs editing the storage)
            // means a click can't invalidate TextKit-2 layout and clamp the scroll (t-6cfaf799).
            (textView as? CodeWellTextView)?.activeLineRange = EditorView.activeLineRange(model)
            // The one storage exception: flip a grid table to/from raw pipes when the caret enters/leaves
            // it (a no-op for ordinary caret moves). The flip CHANGES the table's laid-out height (a
            // compact grid vs raw pipe lines), which would shift the just-clicked line on screen — so
            // bracket it with a caret anchor: measure the caret line's viewport Y before, restore it
            // after by scrolling the clip by exactly the layout delta (t-6cfaf799).
            // Tables AND block-level images flip between their rendered form and raw text when the caret
            // enters/leaves — both change the block's laid-out height, so both go through the same
            // caret-anchored restyle below (t-6cfaf799).
            let flipTables = EditorStyler.activeFlipTables(model: model, previous: previousActive)
                + EditorStyler.activeFlipImages(model: model, previous: previousActive)
            EditorScrollTrace.mark("didChangeSelection sel=\(NSStringFromRange(textView.selectedRange())) flips=\(flipTables.count)")
            if !flipTables.isEmpty, let storage = textView.textStorage {
                // Anchor on the caret's line, VIEWPORT-relative (document Y minus scroll offset — the
                // position the user's eye is on). When the caret sits INSIDE a substituted grid (no
                // text segment to measure), anchor on the table's first character instead — the table
                // top is the same location in both renderings.
                let caret = textView.selectedRange().location
                let clipY = { textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0 }
                let anchor: (location: Int, viewportY: CGFloat)? = Self.lineY(textView, at: caret).map { (caret, $0 - clipY()) }
                    ?? flipTables.first.flatMap { t in Self.lineY(textView, at: t.range.location).map { (t.range.location, $0 - clipY()) } }
                styler.restyleActiveTableFlip(in: storage, tables: flipTables, model: model)
                if let anchor {
                    // The height change only lands during the next VIEWPORT layout pass (an
                    // ensureLayout over the table reads stale origins and a delta of 0), so run that
                    // pass synchronously and compensate before anything draws. The compensating scroll
                    // triggers another viewport pass that can refine positions again — re-measure until
                    // the anchor holds (2 passes typical).
                    textView.needsLayout = true
                    textView.layoutSubtreeIfNeeded()
                    for _ in 0..<4 {
                        guard let y = Self.lineY(textView, at: anchor.location) else { break }
                        let delta = (y - clipY()) - anchor.viewportY
                        guard abs(delta) > 0.5 else { break }
                        EditorScrollTrace.mark(String(format: "table flip anchor Δ %.1f", delta))
                        Self.scrollBy(textView, delta: delta)
                        textView.needsLayout = true
                        textView.layoutSubtreeIfNeeded()
                    }
                }
            }
        }

        /// A character's line Y in text-view coordinates (top of its rendered text segment), or nil
        /// when the location has no measurable segment (e.g. inside a substituted grid attachment).
        private static func lineY(_ textView: NSTextView, at location: Int) -> CGFloat? {
            guard let layoutManager = textView.textLayoutManager,
                  let content = layoutManager.textContentManager,
                  let start = content.location(content.documentRange.location, offsetBy: location) else { return nil }
            var y: CGFloat?
            layoutManager.enumerateTextSegments(in: NSTextRange(location: start), type: .standard, options: []) { _, frame, _, _ in
                y = frame.minY
                return false
            }
            return y.map { $0 + textView.textContainerOrigin.y }
        }

        /// Shift the enclosing clip view by `delta` points (clamped to the scrollable range), keeping
        /// whatever the user clicked at the same screen position. No-op for sub-point deltas.
        private static func scrollBy(_ textView: NSTextView, delta: CGFloat) {
            guard abs(delta) > 0.5, let scrollView = textView.enclosingScrollView else { return }
            let clip = scrollView.contentView
            var target = clip.bounds
            target.origin.y += delta
            clip.scroll(to: clip.constrainBoundsRect(target).origin)
            scrollView.reflectScrolledClipView(clip)
        }

        /// Intercept a mouseDown BEFORE NSTextView's default handling. Returns `true` to consume the
        /// click. Two affordances, both Live-mode only (Source mode is raw editing — no magic):
        /// - PLAIN click inside a task item's `[ ]`/`[x]` cells → toggle it (undo-registered via the
        ///   same `apply(_:)` seam as ⌘K; a 1-for-1 char swap, so the caret/selection stay put).
        /// - **Cmd+click** on a `.link` (content or destination) or `.wikiLink` content span → fire
        ///   `onLinkActivate`. A plain click on a link just places the caret (editing ergonomics win;
        ///   Cmd+click is the editor convention for "follow link").
        func handleMouseDown(at index: Int, commandHeld: Bool) -> Bool {
            guard !model.isSourceMode, let block = model.document.block(at: index) else { return false }
            guard commandHeld else {
                // Plain click: checkbox toggle only.
                guard case .taskItem = block.kind, !model.isReadOnly,
                      let edit = EditorCommands.taskCheckboxToggle(in: model.text, blockRange: block.range,
                                                                   location: index, selection: model.selection)
                else { return false }
                apply(edit)
                return true
            }
            guard let onLinkActivate else { return false }
            let local = index - block.range.location
            let ns = block.text as NSString
            for span in MarkdownInline.spans(in: block.text) {
                switch span.kind {
                case .link:
                    let overDestination = span.destinationRange.map { NSLocationInRange(local, $0) } ?? false
                    guard NSLocationInRange(local, span.contentRange) || overDestination else { continue }
                    // `[text](url)` carries its destination; autolinks/bare URLs ARE their content.
                    let url = ns.substring(with: span.destinationRange ?? span.contentRange)
                    onLinkActivate(.url(url))
                    return true
                case .wikiLink:
                    guard NSLocationInRange(local, span.contentRange) else { continue }
                    onLinkActivate(.wiki(ns.substring(with: span.contentRange)))
                    return true
                default:
                    continue
                }
            }
            return false
        }

        /// Intercept Enter to continue a list/quote (or exit an empty item). Applied undo-registered via
        /// the mutator; anything else falls through to the default editing behavior.
        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               !model.isReadOnly,
               let edit = EditorCommands.newlineContinuation(in: textView.string, selection: textView.selectedRange()) {
                apply(edit)
                return true   // handled — suppress the default newline
            }
            return false
        }
    }
}

// MARK: - ⌘K mutation seam

extension EditorView.Coordinator: EditorTextMutating {

    /// Apply a ⌘K edit through the text view so undo registers and the delegate reparses/restyles via
    /// the normal path. `shouldChangeText`/`didChangeText` bracket the change for the undo manager;
    /// `didChangeText()` posts the change notification that drives `model.updateText`.
    public func apply(_ edit: TextEdit) {
        guard let textView, !model.isReadOnly else { return }   // read-only lock: refuse programmatic edits
        let length = (textView.string as NSString).length
        guard edit.range.location >= 0, NSMaxRange(edit.range) <= length else { return }
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        let after = edit.selectionAfter
        let newLength = (textView.string as NSString).length
        if after.location >= 0, NSMaxRange(after) <= newLength {
            textView.setSelectedRange(after)
        }
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// The caret's position (window top-left space) for anchoring the ⌘K palette — the point cached at
    /// the last caret move (while first responder), or a fresh compute as a fallback.
    public func caretPointInWindow() -> CGPoint? {
        cachedCaretPoint ?? textView.flatMap(computeCaretPoint)
    }

    /// Return first responder to the editor (e.g. after the ⌘K palette closes), so the caret is visible
    /// and positioned where the command left it. Deferred a tick so it runs AFTER SwiftUI tears down the
    /// palette's focused text field (which would otherwise resign focus right after we claim it).
    public func focusEditor() {
        guard let textView else { return }
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
    }

    /// Scroll a source range into view (inspector heading jump). Clamps to the LIVE text length (the
    /// outline is derived from a parse that may momentarily trail the text view mid-edit) so a stale
    /// range can never index out of bounds. Does not touch the selection.
    public func scrollToRange(_ range: NSRange) {
        guard let textView else { return }
        EditorScrollTrace.mark("scrollToRange \(NSStringFromRange(range)) (inspector jump)")
        let length = (textView.string as NSString).length
        let location = max(0, min(range.location, length))
        let clamped = NSRange(location: location, length: min(range.length, length - location))
        textView.scrollRangeToVisible(clamped)
    }

    /// Caret's BOTTOM-LEFT in the window's top-left coordinate space (so the palette can drop just below
    /// it). `firstRect` is screen coords (AppKit bottom-left); flip Y against the content height.
    fileprivate func computeCaretPoint(_ textView: NSTextView) -> CGPoint? {
        guard let window = textView.window else { return nil }
        let screenRect = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil)
        guard screenRect != .zero, screenRect.origin.x.isFinite, screenRect.origin.y.isFinite else { return nil }
        let inWindow = window.convertFromScreen(screenRect)
        let height = window.contentView?.bounds.height ?? window.frame.height
        return CGPoint(x: inWindow.minX, y: height - inWindow.minY)   // caret's lower edge, top-left space
    }
}
