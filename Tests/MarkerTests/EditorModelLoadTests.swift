import Testing
import Foundation
@testable import Marker

/// A reference box so the `@Sendable` observation `onChange` can record that it fired without an
/// escaping-mutable-capture diagnostic. Writes happen synchronously on the main actor during a
/// property mutation, so the `@unchecked` is sound for this test.
private nonisolated final class ObsBox: @unchecked Sendable { var fired = false }

@MainActor
@Suite("EditorModel — load & dirty tracking")
struct EditorModelLoadTests {

    @Test("load swaps contents, resets the caret, and clears the dirty baseline")
    func loadResets() {
        let model = EditorModel(text: "# A\n\nfirst")
        // Dirty it and move the caret.
        model.updateText("# A\n\nfirst edited", selection: NSRange(location: 17, length: 0))
        #expect(model.hasUnsavedChanges)

        model.load(text: "# New\n\nsecond doc")
        #expect(model.text == "# New\n\nsecond doc")
        #expect(model.selection == NSRange(location: 0, length: 0))
        #expect(model.hasUnsavedChanges == false)                 // fresh baseline
        #expect(model.activeBlockID == model.document.blocks.first?.id)
        // DISCRIMINATION: fails if load leaves the previous caret/dirty state (the new doc would open
        // pre-dirtied or scrolled to the old caret).
    }

    @Test("dirty flag tracks divergence from the baseline and flips back on revert")
    func dirtyTracksBaseline() {
        let model = EditorModel(text: "hello")
        #expect(model.hasUnsavedChanges == false)

        model.updateText("hello!", selection: NSRange(location: 6, length: 0))
        #expect(model.hasUnsavedChanges)                          // diverged

        model.updateText("hello", selection: NSRange(location: 5, length: 0))
        #expect(model.hasUnsavedChanges == false)                 // reverted to baseline → clean
        // DISCRIMINATION: fails if dirty is a one-way latch that never clears on revert.
    }

    @Test("markSaved adopts the current text as the new clean baseline")
    func markSavedRebaselines() {
        let model = EditorModel(text: "v1")
        model.updateText("v2", selection: NSRange(location: 2, length: 0))
        #expect(model.hasUnsavedChanges)

        model.markSaved()
        #expect(model.hasUnsavedChanges == false)

        model.updateText("v2", selection: NSRange(location: 2, length: 0))
        #expect(model.hasUnsavedChanges == false)                 // same as the saved baseline
        model.updateText("v3", selection: NSRange(location: 2, length: 0))
        #expect(model.hasUnsavedChanges)                          // diverges from the NEW baseline
        // DISCRIMINATION: fails if markSaved doesn't move the baseline (re-edits to the saved text
        // would wrongly read dirty).
    }

    @Test("an already-dirty keystroke does NOT re-publish hasUnsavedChanges (guarded observation)")
    func dirtyDoesNotChurnObservation() {
        // Positive control: the false→true flip DOES notify, proving observation is actually wired.
        let flipModel = EditorModel(text: "a")
        let flipBox = ObsBox()
        withObservationTracking { _ = flipModel.hasUnsavedChanges } onChange: { flipBox.fired = true }
        flipModel.updateText("ab", selection: NSRange(location: 2, length: 0))
        #expect(flipBox.fired)

        // The guard: a SECOND still-dirty edit must NOT re-notify (the value stays true).
        let model = EditorModel(text: "x")
        model.updateText("xy", selection: NSRange(location: 2, length: 0))       // now dirty
        let box = ObsBox()
        withObservationTracking { _ = model.hasUnsavedChanges } onChange: { box.fired = true }
        model.updateText("xyz", selection: NSRange(location: 3, length: 0))      // still dirty
        #expect(box.fired == false)
        // DISCRIMINATION: drop the `if hasUnsavedChanges != value` guard and setDirty(true) re-writes
        // true every keystroke → onChange fires → the location callout re-renders per character.
    }
}
