import Testing
import Foundation
import CoreGraphics
@testable import Marker

/// Records the edits the palette hands the host and supplies a fixed caret point — stands in for
/// the NSTextView coordinator (the only thing that can apply an undo-registered edit + read the
/// caret rect).
private final class RecordingMutator: EditorTextMutating {
    var applied: [TextEdit] = []
    var focusCount = 0
    var caret: CGPoint? = CGPoint(x: 100, y: 200)
    func apply(_ edit: TextEdit) { applied.append(edit) }
    func caretPointInWindow() -> CGPoint? { caret }
    func focusEditor() { focusCount += 1 }
    func scrollToRange(_ range: NSRange) {}
}

private func palette(loaded text: String = "hello") -> (CommandPaletteModel, EditorModel, RecordingMutator) {
    let editor = EditorModel(text: text)
    let mutator = RecordingMutator()
    editor.mutator = mutator
    return (CommandPaletteModel(editor: editor), editor, mutator)
}

// MARK: - Pure catalog helpers

@Suite("EditorTool — palette filtering & grouping")
struct EditorToolPaletteHelperTests {

    @Test("matching: an empty or whitespace query returns the toolset unchanged")
    func emptyQueryPassesThrough() {
        #expect(EditorTool.matching("", in: EditorTool.cursor) == EditorTool.cursor)
        #expect(EditorTool.matching("   ", in: EditorTool.selection) == EditorTool.selection)
    }

    @Test("matching filters by label, case-insensitively, with surrounding whitespace trimmed")
    func filtersByLabel() {
        #expect(EditorTool.matching("BOLD", in: EditorTool.cursor).map(\.id) == ["bold"])
        #expect(EditorTool.matching("  bold ", in: EditorTool.cursor).map(\.id) == ["bold"])
        // Substring, not prefix: "list" hits bullet/numbered/task list.
        let lists = EditorTool.matching("list", in: EditorTool.cursor).map(\.id)
        #expect(lists == ["ul", "ol", "task"])
        #expect(EditorTool.matching("zzz-no-such-tool", in: EditorTool.cursor).isEmpty)
    }

    @Test("grouped preserves first-appearance order of groups AND of items within a group")
    func groupedPreservesOrder() {
        let groups = EditorTool.grouped(EditorTool.cursor)
        #expect(groups.map(\.group) == ["Format", "Insert"])
        #expect(groups.flatMap(\.items) == EditorTool.cursor)   // nothing lost, nothing reordered

        let selectionGroups = EditorTool.grouped(EditorTool.selection)
        #expect(selectionGroups.map(\.group) == ["Wrap selection", "Turn selection into", "Operate on lines"])
        #expect(selectionGroups.flatMap(\.items) == EditorTool.selection)
    }
}

// MARK: - The turnkey driver

@Suite("CommandPaletteModel — the package palette state machine")
struct CommandPaletteModelTests {

    @Test("present opens at the caret point with a fresh query and highlight")
    func presentOpensAtCaret() {
        let (p, _, mutator) = palette()
        mutator.caret = CGPoint(x: 321, y: 654)
        p.commandQuery = "stale"
        p.moveCommandSelection(2)

        p.present()
        #expect(p.isPresented)
        #expect(p.commandCaret == CGPoint(x: 321, y: 654))
        #expect(p.commandQuery == "")
        #expect(p.commandIndex == 0)
    }

    @Test("present falls back to the fixed anchor when the editor can't supply a caret")
    func presentFallbackAnchor() {
        let (p, _, mutator) = palette()
        mutator.caret = nil
        p.present()
        #expect(p.commandCaret == CGPoint(x: 470, y: 320))   // the default fallbackCaret
    }

    @Test("present refuses a read-only editor (every tool is a mutation)")
    func presentRefusedWhenReadOnly() {
        let (p, editor, _) = palette()
        editor.isReadOnly = true
        p.present()
        #expect(p.isPresented == false)
    }

    @Test("the toolset flips with the editor selection")
    func toolsetFlips() {
        let (p, editor, _) = palette()
        #expect(p.commandSelectionActive == false)
        #expect(p.visibleTools == EditorTool.cursor)
        editor.updateSelection(NSRange(location: 0, length: 3))
        #expect(p.commandSelectionActive)
        #expect(p.visibleTools == EditorTool.selection)
    }

    @Test("setting the query filters the tools and resets the highlight to the first row")
    func queryFiltersAndResets() {
        let (p, _, _) = palette()
        p.moveCommandSelection(3)
        #expect(p.commandIndex == 3)
        p.commandQuery = "bold"
        #expect(p.visibleTools.map(\.id) == ["bold"])
        #expect(p.commandIndex == 0)
    }

    @Test("moveCommandSelection wraps around the visible tools")
    func highlightWraps() {
        let (p, _, _) = palette()
        p.moveCommandSelection(-1)
        #expect(p.commandIndex == EditorTool.cursor.count - 1)   // wrapped to the end
        p.moveCommandSelection(1)
        #expect(p.commandIndex == 0)
    }

    @Test("applyTool runs the command through the mutator, closes, and refocuses the editor")
    func applyToolExecutesAndCloses() {
        let (p, _, mutator) = palette(loaded: "hello")
        p.present()
        p.applyTool(EditorTool.cursor.first { $0.id == "bold" }!)

        let expected = EditorCommands.textEdit(for: .bold, in: "hello", selection: NSRange(location: 0, length: 0))
        #expect(mutator.applied == [expected])
        #expect(p.isPresented == false)
        #expect(mutator.focusCount == 1)   // closing hands focus back so the caret stays visible
    }

    @Test("applyHighlightedTool applies whatever row the highlight sits on")
    func applyHighlighted() {
        let (p, _, mutator) = palette(loaded: "hello")
        p.present()
        p.moveCommandSelection(2)
        let highlighted = p.visibleTools[p.commandIndex].command
        p.applyHighlightedTool()
        let expected = EditorCommands.textEdit(for: highlighted, in: "hello", selection: NSRange(location: 0, length: 0))
        #expect(mutator.applied == [expected])
    }

    @Test("toggle opens then closes; closing always refocuses the editor")
    func toggleAndRefocus() {
        let (p, _, mutator) = palette()
        p.toggle()
        #expect(p.isPresented)
        p.toggle()
        #expect(p.isPresented == false)
        #expect(mutator.focusCount == 1)
    }
}
