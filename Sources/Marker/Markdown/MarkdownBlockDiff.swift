//
//  MarkdownBlockDiff.swift
//  Marker — (ex TrapperKeeperCore) Markdown
//
//  Which blocks a text edit actually changed. A keystroke reparses the whole document, but almost
//  always only ONE block's text differs; every other block is byte-identical (just shifted). The
//  editor uses this to restyle ONLY the changed blocks instead of re-setting attributes over the
//  entire storage — a full restyle invalidates all TextKit-2 layout, collapsing the resizable text
//  view's height so the scroll view clamps toward the top (the "editor jumps when you type" bug on
//  long documents, t-6cfaf799).
//

import Foundation

public extension MarkdownDocument {

    /// The contiguous index range in `blocks` that differs from `previous`, found by a front/back
    /// diff. Two blocks are "the same" when they RENDER the same — equal `kind`, `text`, and `indent`
    /// — so ranges (which every following block shifts by the edit delta) and ids (which are just the
    /// source-order index) are deliberately ignored. Returns `nil` when the block lists render
    /// identically (e.g. an edit that only shifted positions, or no change at all).
    ///
    /// The range is expressed in the NEW (`self`) block indices; a split (`Enter`) widens it to the
    /// two resulting blocks, a merge (`Backspace` at a boundary) covers the merged block, and a whole
    /// block deletion yields an empty span (`nil`) since nothing new needs rendering.
    func changedBlockRange(from previous: [MarkdownBlock]) -> ClosedRange<Int>? {
        let new = blocks
        let overlap = min(previous.count, new.count)

        var front = 0
        while front < overlap, Self.rendersSame(previous[front], new[front]) { front += 1 }

        var back = 0
        while back < overlap - front,
              Self.rendersSame(previous[previous.count - 1 - back], new[new.count - 1 - back]) {
            back += 1
        }

        let lo = front
        let hi = new.count - 1 - back
        return lo <= hi ? lo...hi : nil
    }

    /// Two blocks paint identically iff their kind, source text, and list indent match. `render` in the
    /// styler is a pure function of exactly those (plus the constant style modes), so equal here ⇒ the
    /// already-applied attributes are still correct and the block needs no restyle.
    private static func rendersSame(_ a: MarkdownBlock, _ b: MarkdownBlock) -> Bool {
        a.kind == b.kind && a.text == b.text && a.indent == b.indent
    }
}
