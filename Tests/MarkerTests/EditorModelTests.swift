import Testing
import Foundation
@testable import Marker

@MainActor
@Suite("EditorModel")
struct EditorModelTests {

    @Test("init parses the text and sets the active block to the caret's block")
    func initParses() {
        let model = EditorModel(text: "# Title\n\npara\n")
        #expect(model.document.blocks.count == 3)
        #expect(model.activeBlock?.kind == .heading(level: 1))   // caret at 0 → heading block
    }

    @Test("moving the selection changes the active block")
    func selectionMovesActiveBlock() {
        let model = EditorModel(text: "# Title\n\npara\n")   // heading[0,8) blank[8,9) paragraph[9,14)
        model.updateSelection(NSRange(location: 10, length: 0))
        #expect(model.activeBlock?.kind == .paragraph)
        // DISCRIMINATION: fails if the active-block recompute doesn't follow the caret — the reveal
        // would stay stuck on the wrong line.
    }

    @Test("editing reparses and recomputes the active block")
    func editReparses() {
        let model = EditorModel(text: "para\n")
        #expect(model.activeBlock?.kind == .paragraph)
        model.updateText("# now a heading\n", selection: NSRange(location: 2, length: 0))
        #expect(model.document.blocks.first?.kind == .heading(level: 1))
        #expect(model.activeBlock?.kind == .heading(level: 1))
        // DISCRIMINATION: fails if updateText keeps a stale parse or doesn't recompute the active block.
    }

    @Test("source mode toggles")
    func sourceModeToggles() {
        let model = EditorModel(text: "x")
        #expect(model.isSourceMode == false)
        model.toggleSourceMode()
        #expect(model.isSourceMode)
    }

    @Test("a caret move leaves every full-restyle input untouched (t-6cfaf799 gate)")
    func caretMoveDoesNotPerturbFullRestyleInputs() {
        // The NSTextView host runs the FULL WYSIWYG restyle only when the text is swapped or a style
        // mode (source / hide-markers / indent-headers) changes; a caret move must change NONE of those,
        // so clicking to place the caret in a long doc can't trigger a full-document relayout that snaps
        // the scroll to the top (t-6cfaf799). This locks that contract at the model seam: if a future
        // change let `updateSelection` touch text/parse/modes, the host's gate would wrongly fire (or
        // skip) a full restyle.
        let model = EditorModel(text: "# Title\n\npara one\n\npara two\n")
        let text0 = model.text
        let kinds0 = model.document.blocks.map(\.kind)
        let source0 = model.isSourceMode
        let hide0 = model.hideMarkers
        let indent0 = model.indentHeaders
        let active0 = model.activeBlockID

        model.updateSelection(NSRange(location: 22, length: 0))   // caret into the last paragraph block

        #expect(model.activeBlockID != active0)                    // a REAL caret move happened…
        #expect(model.text == text0)                               // …and no full-restyle input moved:
        #expect(model.document.blocks.map(\.kind) == kinds0)
        #expect(model.isSourceMode == source0)
        #expect(model.hideMarkers == hide0)
        #expect(model.indentHeaders == indent0)
    }
}
