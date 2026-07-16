//
//  CommandPalette.swift
//  Marker — the command palette's state machine (extracted from TrapperKeeper's AppStore, 0.6.0)
//
//  Two pieces, both UI-free so they live in the core (the themed panel itself is
//  MarkerEditor's `CommandPaletteView`):
//
//  • `CommandPaletteDriving` — the surface the palette VIEW binds to. Named to match the
//    original AppStore members verbatim, so a consumer that already owns a palette state
//    machine (TrapperKeeper's AppStore) conforms with an empty extension and keeps its own
//    open/close policy, contextual tools, and post-apply behavior (toasts, async pickers).
//  • `CommandPaletteModel` — a ready-made driver over one `EditorModel` for consumers without
//    their own store (ShabuBox): present at the caret, type-to-filter the `EditorTool` catalog,
//    move/apply/dismiss, executing through `EditorModel.runCommand` (the undo-registered
//    mutator seam) and returning focus to the editor on close.
//

import Foundation
import CoreGraphics
import Observation

// MARK: - Pure catalog helpers (shared by the drivers and the palette view)

/// One palette section: a group label plus its tools, in catalog order.
public nonisolated struct EditorToolGroup: Identifiable, Equatable, Sendable {
    public let group: String
    public let items: [EditorTool]
    public var id: String { group }

    public init(group: String, items: [EditorTool]) {
        self.group = group
        self.items = items
    }
}

public extension EditorTool {

    /// The tools whose label matches `query` (trimmed, case-insensitive substring). An empty /
    /// whitespace query returns `tools` unchanged — the palette shows the full catalog then.
    nonisolated static func matching(_ query: String, in tools: [EditorTool]) -> [EditorTool] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return tools }
        return tools.filter { $0.label.lowercased().contains(q) }
    }

    /// Tools grouped by section, preserving first-appearance order (so groups render
    /// top-to-bottom exactly as the catalog lists them).
    nonisolated static func grouped(_ tools: [EditorTool]) -> [EditorToolGroup] {
        var order: [String] = []
        var byGroup: [String: [EditorTool]] = [:]
        for tool in tools {
            if byGroup[tool.group] == nil { order.append(tool.group) }
            byGroup[tool.group, default: []].append(tool)
        }
        return order.map { EditorToolGroup(group: $0, items: byGroup[$0] ?? []) }
    }
}

// MARK: - The surface the palette view drives

/// What `CommandPaletteView` needs from its state owner. Class-bound + `Observable` so the view
/// re-renders off property access; @MainActor like every editor seam. Member names mirror the
/// original TrapperKeeper AppStore palette API one-for-one (that store conforms as-is).
@MainActor
public protocol CommandPaletteDriving: AnyObject, Observable {
    /// The filter query (the view's search field binds here). Setting it must reset the
    /// highlight to the first row — the design behavior on every keystroke.
    var commandQuery: String { get set }
    /// Whether the selection toolset is active (flips the palette's header/footer copy).
    var commandSelectionActive: Bool { get }
    /// The tools matching the current query (the full toolset when the query is empty).
    var visibleTools: [EditorTool] { get }
    /// The highlighted row index into `visibleTools`.
    var commandIndex: Int { get }
    /// Window-space anchor point for the panel (the caret, top-left coordinate space).
    var commandCaret: CGPoint { get }
    /// Move the highlight within the visible tools (wrapping).
    func moveCommandSelection(_ delta: Int)
    /// Apply the highlighted tool (⏎).
    func applyHighlightedTool()
    /// Apply a specific tool (row click).
    func applyTool(_ tool: EditorTool)
    /// Close the palette (Esc / scrim click) and return focus to the editor.
    func closeCommandPalette()
}

// MARK: - Ready-made driver over one EditorModel

/// The turnkey palette state machine for consumers without their own store: owns
/// presented/query/highlight/caret state over one `EditorModel`, executes tools through
/// `EditorModel.runCommand` (undo-registered via the mutator seam), and returns focus to the
/// editor on close. The CONSUMER owns the trigger (a menu item, a keyboard shortcut) and the
/// presentation surface (`if palette.isPresented { CommandPaletteView(...) }`) — the model
/// hardcodes no key.
@MainActor
@Observable
public final class CommandPaletteModel: CommandPaletteDriving {

    /// Whether the palette is showing — the consumer's overlay condition.
    public private(set) var isPresented = false
    /// The filter query. Setting it resets the highlight to the first row (design behavior).
    public var commandQuery = "" { didSet { if commandIndex != 0 { commandIndex = 0 } } }
    /// The highlighted row in `visibleTools`.
    public private(set) var commandIndex = 0
    /// Window-space anchor point for the panel (captured from the caret at present time).
    public private(set) var commandCaret: CGPoint = .zero
    /// Where the panel anchors when the editor can't supply a caret point (not hosted yet, or
    /// the caret rect is unmeasurable). Mirrors the original app's fixed fallback.
    public var fallbackCaret: CGPoint

    /// The editor the palette mutates. Strong: the palette is a peer owned by the same host
    /// that owns the editor; the editor never references the palette back (no cycle).
    private let editor: EditorModel

    public init(editor: EditorModel, fallbackCaret: CGPoint = CGPoint(x: 470, y: 320)) {
        self.editor = editor
        self.fallbackCaret = fallbackCaret
    }

    /// Whether there's a live text selection (the palette flips to the selection toolset).
    public var commandSelectionActive: Bool { editor.selection.length > 0 }

    /// The toolset for the current mode (caret vs selection).
    public var activeTools: [EditorTool] {
        commandSelectionActive ? EditorTool.selection : EditorTool.cursor
    }

    /// The tools matching the query (all of `activeTools` when the query is empty).
    public var visibleTools: [EditorTool] { EditorTool.matching(commandQuery, in: activeTools) }

    /// Show the palette at the caret with a fresh query/highlight. Refused on a read-only
    /// document — every tool is a mutation, so the palette must not open over a locked editor.
    public func present() {
        guard !editor.isReadOnly else { return }
        commandCaret = editor.caretPointInWindow() ?? fallbackCaret
        commandQuery = ""
        commandIndex = 0
        isPresented = true
    }

    /// Toggle — the natural binding for a single show/hide shortcut.
    public func toggle() {
        if isPresented { closeCommandPalette() } else { present() }
    }

    public func closeCommandPalette() {
        isPresented = false
        editor.focusEditor()   // return the caret to the editor so it stays visible + positioned
    }

    /// Move the highlight within the visible tools (wraps).
    public func moveCommandSelection(_ delta: Int) {
        let n = visibleTools.count
        guard n > 0 else { return }
        commandIndex = (commandIndex + delta + n) % n
    }

    /// Apply the highlighted tool (⏎).
    public func applyHighlightedTool() {
        guard visibleTools.indices.contains(commandIndex) else { return }
        applyTool(visibleTools[commandIndex])
    }

    /// Apply a tool: close the palette (which refocuses the editor), then run the tool's
    /// command through the undo-registered mutator seam.
    public func applyTool(_ tool: EditorTool) {
        closeCommandPalette()
        editor.runCommand(tool.command)
    }
}
