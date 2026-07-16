//
//  EditorModel.swift
//  Marker — (ex TrapperKeeperCore) Editor (P1.2)
//
//  The editor's state, platform-agnostic so the macOS NSTextView host (and a future iOS UITextView
//  host) bind to the same logic. The raw `text` is canonical; `document` is the derived parse used
//  for styling; `activeBlockID` is the block holding the caret — the key the cursor-line source
//  reveal (P1.3) keys off.
//
//  Reparsing is full-document for now (naive); P1.4 measures latency and makes it incremental.
//

import Foundation
import CoreGraphics
import Observation

/// The seam the ⌘K command engine mutates the live document through. Implemented by the NSTextView
/// host's coordinator (the only thing that can apply an undo-registered edit + read the caret rect);
/// the `EditorModel` holds a weak reference and never imports AppKit. @MainActor + AnyObject — the
/// text view is main-actor, and the model holds it weakly.
@MainActor
public protocol EditorTextMutating: AnyObject {
    /// Apply a precise edit to the live text storage (undo-registered) and move the selection.
    func apply(_ edit: TextEdit)
    /// The caret's position in the window's top-left coordinate space, for anchoring the ⌘K palette.
    func caretPointInWindow() -> CGPoint?
    /// Return first responder to the editor (e.g. after a ⌘K palette closes) so the caret stays visible.
    func focusEditor()
    /// Scroll a source range into view (the inspector's click-to-jump on a heading). Does NOT move the
    /// caret/selection — jumping to read a section shouldn't relocate the edit point.
    func scrollToRange(_ range: NSRange)
}

/// An image dropped onto the editor, captured WHILE the drop's sandbox grant is live: the URL plus a
/// security-scoped bookmark minted synchronously in the drop handler. The async insert then persists
/// the bookmark + reads the bytes — the raw grant may already be gone by then, which is why the blob
/// is minted up front (see t-c6f28efb Phase D audit).
public nonisolated struct CapturedImageDrop: Sendable {
    public let url: URL
    public let bookmark: Data
    public init(url: URL, bookmark: Data) {
        self.url = url
        self.bookmark = bookmark
    }
}

@MainActor
@Observable
public final class EditorModel {

    /// The canonical raw markdown — exactly the file's bytes. Saving writes this verbatim.
    public private(set) var text: String
    /// Derived block parse of `text`, kept in sync on every edit.
    public private(set) var document: MarkdownDocument
    /// Caret / selection in UTF-16 offsets (NSTextView's coordinate space).
    public private(set) var selection: NSRange
    /// The id of the block containing the caret (drives the cursor-line source reveal). nil only for
    /// an empty document.
    public private(set) var activeBlockID: Int?
    /// Live (WYSIWYG, active line revealed) vs Source (whole file raw). Toggled by ⌘↵.
    public var isSourceMode = false
    /// When true, syntax markers render invisible (not dimmed) in the WYSIWYG view. The marker chars
    /// stay in the storage (bytes + caret positions unchanged) — only their color goes clear. Read by
    /// the styler; toggling it re-styles via the same observation path as `isSourceMode`.
    public var hideMarkers = false
    /// Whether headings keep the leading space of their `#` marker. When false AND markers are hidden,
    /// the marker collapses to zero width so the heading sits flush-left with body text (bytes + caret
    /// positions unchanged — only the glyph advance goes to ~0). Default true (preserves the indent).
    /// Read by the styler; toggling re-styles via the same observation path as `hideMarkers`.
    public var indentHeaders = true
    /// True when `text` has diverged from the last opened/saved baseline. Internal signal that gates
    /// ⌘S (no-op when clean); NOT surfaced as a "dirty" chip in P2. Guarded so it flips rarely
    /// instead of churning observation on every keystroke.
    public private(set) var hasUnsavedChanges = false

    /// When true, the document is READ-ONLY: typing, ⌘K mutations, and image inserts are all refused
    /// (the file stays openable/scrollable/copyable). Driven by the app from `LicenseManager.status`
    /// after the trial expires or a license is revoked (the hard pay-to-own lock). The editor doesn't
    /// know WHY it's locked (licensing lives in the app layer) — only that mutations are off. The
    /// NSTextView host reads this to set `isEditable`; `runCommand`/`insertImageReference` gate on it.
    public var isReadOnly = false

    /// Resolved image bytes for the open document's block-level images, keyed by the RAW `![](path)`
    /// destination string. Populated by `AppStore` after open (local, in-scope images only); the editor
    /// host renders these inline and shows a placeholder for any path not present here. Stored as bytes,
    /// not `NSImage`, to keep this core type platform-agnostic.
    public private(set) var imageData: [String: Data] = [:]

    /// The bytes as of the last load/save — the dirty baseline. Not observed (an implementation
    /// detail, not UI state).
    @ObservationIgnored private var savedBaseline: String

    /// The host that applies ⌘K edits to the live text view. Weak + not observed — a wiring dependency,
    /// set by the NSTextView host on creation; nil in headless/test construction.
    @ObservationIgnored public weak var mutator: (any EditorTextMutating)?

    /// Set by AppStore: images dropped onto the editor (with a bookmark already minted in the drop
    /// handler) are handed here to be persisted + inserted. A wiring dependency like `mutator`; not observed.
    @ObservationIgnored public var onDropImages: (([CapturedImageDrop]) -> Void)?

    public init(text: String) {
        self.text = text
        self.document = MarkdownParser.parse(text)
        self.selection = NSRange(location: 0, length: 0)
        self.savedBaseline = text
        self.activeBlockID = document.block(at: 0)?.id
    }

    /// Swap in a different document's contents (open / close): reset text, caret, and the dirty
    /// baseline. The host's `updateNSView` picks up the new `text` and re-styles; switching documents
    /// this way (vs `.id()`-resetting the view) keeps the NSTextView alive (see view discipline).
    public func load(text newText: String) {
        text = newText
        document = MarkdownParser.parse(newText)
        selection = NSRange(location: 0, length: 0)
        activeBlockID = document.block(at: 0)?.id
        savedBaseline = newText
        imageData = [:]   // drop the previous doc's images; AppStore repopulates for the new doc
        setDirty(false)
    }

    /// Mark the current `text` as the saved baseline (after a successful write).
    public func markSaved() {
        savedBaseline = text
        setDirty(false)
    }

    /// The text view edited: adopt its new contents + caret, and reparse.
    public func updateText(_ newText: String, selection newSelection: NSRange) {
        text = newText
        document = MarkdownParser.parse(newText)
        selection = newSelection
        recomputeActiveBlock()
        setDirty(newText != savedBaseline)
    }

    /// The caret/selection moved (no text change): just recompute the active block.
    public func updateSelection(_ newSelection: NSRange) {
        selection = newSelection
        recomputeActiveBlock()
    }

    /// Adopt the resolved image bytes for the open doc (keyed by raw `![](path)` destination). Called by
    /// AppStore right after `load(text:)` with no intervening await, so the first layout already has them.
    public func setImages(_ images: [String: Data]) {
        imageData = images
    }

    /// Merge one resolved image's bytes (an insert via ⌘K / drag-drop), keyed by its raw destination —
    /// so the block renders as soon as the insert relayout runs, not just on the next open.
    public func addImage(url: String, data: Data) {
        imageData[url] = data
    }

    /// Insert a block-level image reference at the caret on its OWN paragraph, leaving the caret on the
    /// line AFTER it (so the block is inactive and renders immediately). Applied through the mutator so
    /// undo registers and the normal reparse/restyle runs. No-op when not hosted (tests).
    public func insertImageReference(url: String) {
        guard !isReadOnly, let mutator else { return }
        let ns = text as NSString
        // Insert at a ZERO-LENGTH point at the caret — a block-image insert must NEVER delete a
        // selection (defensive; callers already collapse the caret before inserting).
        let loc = min(max(selection.location, 0), ns.length)
        // Own paragraph: a line break before if we're mid-line, a blank line after if non-blank text
        // follows (else the parser merges the image line with it and it renders raw).
        let lead = (loc > 0 && ns.character(at: loc - 1) != 0x0A) ? "\n" : ""
        let trail = (loc < ns.length && ns.character(at: loc) != 0x0A) ? "\n" : ""
        let core = "![](\(url))\n"
        let caret = loc + (lead as NSString).length + (core as NSString).length   // start of next line
        mutator.apply(TextEdit(range: NSRange(location: loc, length: 0), replacement: lead + core + trail,
                               selectionAfter: NSRange(location: caret, length: 0)))
    }

    public func toggleSourceMode() { isSourceMode.toggle() }

    /// Run a ⌘K command: compute the precise edit from the CURRENT text + selection and apply it through
    /// the host (so undo registers and the delegate reparses/restyles via the normal path). Returns
    /// whether an edit was applied (`false` = the command didn't apply, e.g. a no-op insert).
    @discardableResult
    public func runCommand(_ command: EditorCommand) -> Bool {
        guard !isReadOnly else { return false }
        guard let edit = EditorCommands.textEdit(for: command, in: text, selection: selection) else { return false }
        mutator?.apply(edit)
        return true
    }

    /// The caret's window-space position (for anchoring the ⌘K palette), or nil when not hosted.
    public func caretPointInWindow() -> CGPoint? { mutator?.caretPointInWindow() }

    /// Return keyboard focus to the editor (no-op when not hosted / in tests).
    public func focusEditor() { mutator?.focusEditor() }

    /// Scroll a source range into view (inspector heading jump). No-op when not hosted / in tests.
    public func scrollTo(range: NSRange) { mutator?.scrollToRange(range) }

    /// The block the caret currently sits in.
    public var activeBlock: MarkdownBlock? {
        guard let activeBlockID else { return nil }
        return document.blocks.first { $0.id == activeBlockID }
    }

    private func recomputeActiveBlock() {
        activeBlockID = document.block(at: selection.location)?.id
    }

    /// Guard the write so the dirty flag only notifies observers when it actually changes — keystrokes
    /// on an already-dirty document must not re-render anything reading `hasUnsavedChanges`.
    private func setDirty(_ value: Bool) {
        if hasUnsavedChanges != value { hasUnsavedChanges = value }
    }
}
