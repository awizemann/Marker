import Testing
import Foundation
@testable import Marker

@Suite("Markdown parser")
struct MarkdownParserTests {

    /// THE file-fidelity guarantee: concatenating block slices reproduces the source exactly, and
    /// the blocks tile [0, length) with no gaps or overlaps.
    private func assertTiles(_ source: String) {
        let doc = MarkdownParser.parse(source)
        let ns = source as NSString
        #expect(doc.blocks.map(\.text).joined() == source, "round-trip mismatch for \(source.debugDescription)")
        var cursor = 0
        for block in doc.blocks {
            #expect(block.range.location == cursor, "gap/overlap at block \(block.id) in \(source.debugDescription)")
            cursor = NSMaxRange(block.range)
        }
        #expect(cursor == ns.length, "blocks don't cover to EOF for \(source.debugDescription)")
    }

    @Test("byte-exact tiling across a representative corpus, incl. CRLF and no trailing newline")
    func tilesCorpus() {
        assertTiles("")
        assertTiles("# Title\n\nA paragraph with **bold**.\n")
        assertTiles("- a\n- b\n- c\n")
        assertTiles("1. one\n2. two\n")
        assertTiles("- [ ] todo\n- [x] done\n")
        assertTiles("> quote 1\n> quote 2\n\npara\n")
        assertTiles("```swift\nlet x = 1  // # not a heading\n```\n")
        assertTiles("| a | b |\n| - | - |\n| 1 | 2 |\n")
        assertTiles("para line 1\npara line 2\n\n---\n\nnext\n")
        assertTiles("no trailing newline")
        assertTiles("line1\r\nline2\r\n")     // CRLF must survive byte-for-byte
        assertTiles("\n\n\n")
        assertTiles("- a\n  - b\n    - c\n")   // nested lists must still tile byte-for-byte
        // A rich mixed document exercising every block-kind boundary at once.
        assertTiles("# H\n\n- a\n  - b\n\n| x | y |\n|---|---|\n| 1 | 2 |\n\n```js\ncode\n```\n\n> q\n")
        // DISCRIMINATION: any grouping bug that drops, double-counts, or normalizes a byte breaks
        // joined()==source or the contiguity walk.
    }

    @Test("blocks classify to the right kinds")
    func classification() {
        func kinds(_ s: String) -> [BlockKind] { MarkdownParser.parse(s).blocks.map(\.kind) }
        #expect(kinds("# H1\n") == [.heading(level: 1)])
        #expect(kinds("### H3\n") == [.heading(level: 3)])
        #expect(kinds("###### H6\n") == [.heading(level: 6)])   // all six ATX levels
        #expect(kinds("####### too many\n") == [.paragraph])    // 7 hashes is not a heading
        #expect(kinds("#nospace\n") == [.paragraph])            // ATX needs a space
        #expect(kinds("- item\n") == [.bulletItem(marker: "-")])
        #expect(kinds("* item\n") == [.bulletItem(marker: "*")])
        #expect(kinds("2. item\n") == [.orderedItem(number: 2)])
        #expect(kinds("- [ ] t\n") == [.taskItem(checked: false)])
        #expect(kinds("- [x] t\n") == [.taskItem(checked: true)])
        #expect(kinds("---\n") == [.thematicBreak])
        #expect(kinds("> q\n") == [.blockquote])
        #expect(kinds("plain text\n") == [.paragraph])
    }

    @Test("a fenced block with markdown-looking interior stays ONE code block")
    func codeFenceIsOneBlock() {
        let doc = MarkdownParser.parse("```\n# heading?\n- list?\n```\n")
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks.first?.kind == .codeBlock(language: nil))
        // DISCRIMINATION: fails if the parser classifies the fence interior — the classic
        // "styling leaks into code" bug (interior lines would become heading/list blocks).
    }

    @Test("fence language is captured from the opening fence")
    func fenceLanguageCaptured() {
        #expect(MarkdownParser.parse("```swift\nlet x = 1\n```\n").blocks.first?.kind == .codeBlock(language: "swift"))
    }

    @Test("consecutive blockquote / table lines group into one block")
    func greedyGrouping() {
        #expect(MarkdownParser.parse("> a\n> b\n> c\n").blocks.count == 1)
        #expect(MarkdownParser.parse("| a |\n| b |\n").blocks.count == 1)
        #expect(MarkdownParser.parse("p1\np2\np3\n").blocks.filter { $0.kind == .paragraph }.count == 1)
    }

    @Test("nested list items are recognized past 3 spaces and record their indent depth")
    func nestedListIndent() {
        let src = "- top\n  - two\n    - four\n"
        let doc = MarkdownParser.parse(src)
        #expect(doc.blocks.map(\.kind) == [.bulletItem(marker: "-"), .bulletItem(marker: "-"), .bulletItem(marker: "-")])
        #expect(doc.blocks.map(\.indent) == [0, 2, 4])
        assertTiles(src)   // a 4-space sub-item is still a list item (not dropped) AND still tiles

        // ordered + task nesting record indent too
        let mixed = "1. a\n    2. b\n  - [ ] c\n"
        let d2 = MarkdownParser.parse(mixed)
        #expect(d2.blocks.map(\.kind) == [.orderedItem(number: 1), .orderedItem(number: 2), .taskItem(checked: false)])
        #expect(d2.blocks.map(\.indent) == [0, 4, 2])
        assertTiles(mixed)
        // DISCRIMINATION: fails if a nested item drops to paragraph (flat lists), the indent isn't
        // captured (no nesting depth), or the deeper indent breaks byte-exact tiling.
    }

    @Test("a top-level list item has indent 0 (no phantom nesting)")
    func topLevelIndentZero() {
        #expect(MarkdownParser.parse("- a\n- b\n").blocks.allSatisfy { $0.indent == 0 })
    }

    @Test("block(at:) finds the block holding a caret offset, incl. EOF")
    func blockAtCaret() {
        let src = "# Title\n\npara\n"        // heading[0,8) · blank[8,9) · paragraph[9,14)
        let doc = MarkdownParser.parse(src)
        #expect(doc.block(at: 0)?.kind == .heading(level: 1))
        #expect(doc.block(at: 3)?.kind == .heading(level: 1))
        #expect(doc.block(at: 9)?.kind == .paragraph)
        #expect(doc.block(at: (src as NSString).length)?.kind == .paragraph)   // caret at EOF → last block
        // DISCRIMINATION: fails if range containment or the EOF fallback is wrong — the cursor-line
        // reveal would highlight the wrong block (or none).
    }
}
