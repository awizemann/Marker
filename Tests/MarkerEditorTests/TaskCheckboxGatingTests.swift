import Testing
import AppKit
@testable import Marker
@testable import MarkerEditor

/// `EditorView.taskCheckboxes` decides where a drawn checkbox replaces the literal `[ ]`/`[x]` text.
/// Three gates, all of which must hold: Live mode (Source mode shows the file raw), hide-markers on
/// (with markers shown the literal cell is the point), and an EDITABLE document — the click handler
/// refuses to toggle under the read-only lock, so a checkbox there would be an inert control.
@MainActor
@Suite("Task checkbox mode gating")
struct TaskCheckboxGatingTests {

    private let text = "notes\n\n- [ ] open\n- [x] done\n"

    private func model(source: Bool = false, hideMarkers: Bool = true, readOnly: Bool = false) -> EditorModel {
        let model = EditorModel(text: text)
        model.isSourceMode = source
        model.hideMarkers = hideMarkers
        model.isReadOnly = readOnly
        return model
    }

    @Test("Live + hide-markers + editable → one cell per task item, checked state carried through")
    func liveHiddenEditable() {
        let cells = EditorView.taskCheckboxes(model())
        #expect(cells.count == 2)
        #expect(cells.map(\.checked) == [false, true])
        let ns = text as NSString
        #expect(ns.substring(with: cells[0].cell) == "[ ]")
        #expect(ns.substring(with: cells[1].cell) == "[x]")
    }

    @Test("Source mode draws nothing")
    func sourceMode() {
        #expect(EditorView.taskCheckboxes(model(source: true)).isEmpty)
    }

    @Test("markers visible draws nothing")
    func markersVisible() {
        #expect(EditorView.taskCheckboxes(model(hideMarkers: false)).isEmpty)
    }

    @Test("read-only draws nothing — the click handler wouldn't toggle it")
    func readOnly() {
        #expect(EditorView.taskCheckboxes(model(readOnly: true)).isEmpty)
    }

    @Test("read-only keeps the literal cell text VISIBLE, so nothing is left blank")
    func readOnlyKeepsCellVisible() throws {
        let ns = text as NSString
        let cellRange = ns.range(of: "[ ]")

        func cellColor(readOnly: Bool) -> NSColor? {
            let model = model(readOnly: readOnly)
            let storage = NSTextStorage(string: text)
            EditorStyler(theme: MarkerTheme.fallback).apply(to: storage, model: model)
            return storage.attribute(.foregroundColor, at: cellRange.location, effectiveRange: nil) as? NSColor
        }
        // Editable: the cell is painted clear and the drawn checkbox stands in for it.
        #expect(cellColor(readOnly: false)?.alphaComponent == 0)
        // Read-only: no checkbox is drawn, so the text must still be readable.
        #expect((cellColor(readOnly: true)?.alphaComponent ?? 0) > 0)
    }
}
