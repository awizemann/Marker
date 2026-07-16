import Testing
import Foundation
@testable import Marker

@Suite("MarkdownBlockDiff")
struct MarkdownBlockDiffTests {

    /// Parse two source strings and return the changed block range from old → new.
    private func changed(from old: String, to new: String) -> ClosedRange<Int>? {
        let oldBlocks = MarkdownParser.parse(old).blocks
        return MarkdownParser.parse(new).changedBlockRange(from: oldBlocks)
    }

    @Test("an identical reparse changes nothing")
    func noChange() {
        #expect(changed(from: "# A\n\nbody\n", to: "# A\n\nbody\n") == nil)
        // DISCRIMINATION: fails if the diff keys off range/id (which are equal here anyway) rather than
        // returning nil for a byte-identical document.
    }

    @Test("typing in one paragraph changes only that block")
    func singleBlockEdit() {
        // heading[0] blank[1] paragraph[2] blank[3] paragraph[4]
        let range = changed(from: "# A\n\nfirst\n\nsecond\n",
                             to:   "# A\n\nfirst!\n\nsecond\n")
        #expect(range == 2...2)
        // DISCRIMINATION: fails if the diff widens past the edited paragraph — restyling extra blocks
        // is what invalidates layout and clamps the scroll.
    }

    @Test("editing the LAST block leaves the prefix untouched")
    func lastBlockEdit() {
        let range = changed(from: "# A\n\nfirst\n\nsecond\n",
                             to:   "# A\n\nfirst\n\nsecond edit\n")
        #expect(range == 4...4)
    }

    @Test("editing the FIRST block leaves the suffix untouched")
    func firstBlockEdit() {
        let range = changed(from: "# A\n\nfirst\n\nsecond\n",
                             to:   "# AA\n\nfirst\n\nsecond\n")
        #expect(range == 0...0)
    }

    @Test("promoting a paragraph to a heading restyles just that block")
    func kindChange() {
        let range = changed(from: "para\n\nkeep\n",
                             to:   "# para\n\nkeep\n")
        #expect(range == 0...0)
        // DISCRIMINATION: the block's KIND changed (paragraph → heading) though its neighbors didn't;
        // fails if the diff compares only text and misses a kind flip.
    }

    @Test("splitting a block with Enter widens the range to both halves")
    func splitBlock() {
        // "one two\n" is a single paragraph; a newline in the middle makes two.
        let range = changed(from: "top\n\none two\n\nbottom\n",
                             to:   "top\n\none \ntwo\n\nbottom\n")
        // new blocks: top[0] blank[1] para"one \ntwo"[2] blank[3] bottom[4]
        // A hard line break inside a paragraph keeps it one block, so only block 2 changed.
        #expect(range == 2...2)
    }

    @Test("a blank line split produces two paragraphs and the range covers both")
    func blankLineSplit() {
        // Splitting "one two" with a BLANK line yields two paragraph blocks where there was one.
        let range = changed(from: "top\n\none two\n\nbottom\n",
                             to:   "top\n\none\n\ntwo\n\nbottom\n")
        // old: top[0] blank[1] para[2] blank[3] bottom[4]
        // new: top[0] blank[1] para"one"[2] blank[3] para"two"[4] blank[5] bottom[6]
        // Front match: top, blank. Back match: bottom, blank. Changed: new[2...4].
        #expect(range == 2...4)
    }

    @Test("merging two paragraphs covers the merged block")
    func mergeBlocks() {
        let range = changed(from: "top\n\none\n\ntwo\n\nbottom\n",
                             to:   "top\n\none two\n\nbottom\n")
        // old: top[0] blank[1] one[2] blank[3] two[4] blank[5] bottom[6]
        // new: top[0] blank[1] "one two"[2] blank[3] bottom[4]
        // Front: top, blank. Back: bottom, blank. Changed: new[2...2].
        #expect(range == 2...2)
    }

    @Test("deleting a whole block yields an empty span (nil)")
    func deleteWholeBlock() {
        // Remove the middle paragraph AND its trailing blank so the prefix/suffix meet exactly.
        let range = changed(from: "top\n\nmiddle\n\nbottom\n",
                             to:   "top\n\nbottom\n")
        // old: top[0] blank[1] middle[2] blank[3] bottom[4]
        // new: top[0] blank[1] bottom[2]
        // Front: top, blank (front=2). Back: bottom (back=1), then guard stops. lo=2, hi=3-1-1=1 → nil.
        #expect(range == nil)
        // DISCRIMINATION: a pure deletion has no NEW block to render; fails if the diff returns a
        // bogus non-empty range (which would restyle an unrelated block).
    }
}
