import Testing
import Foundation
@testable import Marker

@Suite("Markdown table model")
struct MarkdownTableTests {

    // MARK: Happy path

    @Test("parses header, alignments, and data rows with trimmed cell text")
    func basic() {
        let src = "| Name | Age |\n| --- | --- |\n| Ada | 36 |\n| Bo | 9 |\n"
        let t = try! #require(MarkdownTable.parse(src))
        #expect(t.columnCount == 2)
        #expect(t.header.map(\.text) == ["Name", "Age"])
        #expect(t.rows.map { $0.map(\.text) } == [["Ada", "36"], ["Bo", "9"]])
        // DISCRIMINATION: a splitter that keeps the surrounding spaces, or one that treats the
        // separator as a data row, breaks these exact strings / the row count.
        #expect(t.alignments == [.left, .left])
    }

    @Test("per-column alignment from the :---: separator")
    func alignments() {
        let src = "| L | C | R | D |\n|:---|:--:|---:|----|\n| 1 | 2 | 3 | 4 |\n"
        let t = try! #require(MarkdownTable.parse(src))
        #expect(t.alignments == [.left, .center, .right, .left])
        // DISCRIMINATION: fails if colon parsing is inverted (leading→right), if center isn't
        // detected, or if the default (no colons) isn't left.
    }

    @Test("the trailing outer pipe is optional (the leading pipe is required by the block parser)")
    func trailingPipeOptional() {
        // The block parser (MarkdownParser.isTableRow) requires a leading `|` on every line, so THAT
        // is the contract the render exercises; the trailing pipe is genuinely optional.
        let withTrailing = try! #require(MarkdownTable.parse("| a | b |\n| - | - |\n| 1 | 2 |\n"))
        let noTrailing   = try! #require(MarkdownTable.parse("| a | b\n| - | -\n| 1 | 2\n"))
        #expect(withTrailing.header.map(\.text) == noTrailing.header.map(\.text))
        #expect(withTrailing.rows.map { $0.map(\.text) } == noTrailing.rows.map { $0.map(\.text) })
        #expect(noTrailing.columnCount == 2)
        // DISCRIMINATION: a splitter that assumes a trailing pipe would emit a phantom empty last
        // column for the no-trailing form, so the two shapes' column counts would diverge.
    }

    @Test("a borderless (no leading pipe) table is NOT grouped as a table block — known limitation")
    func borderlessNotGroupedByParser() {
        let blocks = MarkdownParser.parse("a | b\n--- | ---\n1 | 2\n").blocks
        #expect(!blocks.contains { $0.kind == .table })
        // The block parser requires a leading `|`, so the grid render is scoped to leading-pipe
        // tables. Locks that contract: a future borderless-table feature must be a deliberate change,
        // not an accident. (Guards against HIGH-1 "dead feature" drift found in the audit.)
    }

    // MARK: Escapes

    @Test("a backslash-escaped pipe stays inside one cell and displays as a literal pipe")
    func escapedPipe() {
        let src = "| a \\| b | c |\n| --- | --- |\n"
        let t = try! #require(MarkdownTable.parse(src))
        #expect(t.columnCount == 2)                    // NOT 3 — the \| is not a delimiter
        #expect(t.header.map(\.text) == ["a | b", "c"]) // display text is unescaped
        // The source range still points at the RAW (escaped) bytes, so a write-back is byte-safe.
        let raw = (src as NSString).substring(with: t.header[0].range)
        #expect(raw == "a \\| b")
        // DISCRIMINATION: fails if the escape is ignored (3 columns) or if range/text conflate raw
        // and display (raw would show the unescaped pipe, or text would keep the backslash).
    }

    @Test("an even backslash run before a pipe is NOT an escape (real delimiter)")
    func doubleBackslashIsRealDelimiter() {
        // `a\\` = a literal backslash, then a real column break, then `b`.
        let src = "| a\\\\ | b |\n| - | - |\n"
        let t = try! #require(MarkdownTable.parse(src))
        #expect(t.columnCount == 2)
        #expect(t.header.map(\.text) == ["a\\\\", "b"])
        // DISCRIMINATION: a naive "preceded by one backslash" check would swallow the delimiter and
        // report a single column.
    }

    // MARK: Ragged rows

    @Test("data rows are padded/truncated to the header's column count")
    func raggedRows() {
        let src = "| a | b | c |\n|---|---|---|\n| 1 |\n| 1 | 2 | 3 | 4 |\n"
        let t = try! #require(MarkdownTable.parse(src))
        #expect(t.columnCount == 3)
        #expect(t.rows[0].map(\.text) == ["1", "", ""])       // short row padded
        #expect(t.rows[1].map(\.text) == ["1", "2", "3"])     // long row truncated
        // DISCRIMINATION: fails if rows aren't normalized — a grid renderer keyed on columnCount
        // would index out of bounds on the short row or draw a ragged extra cell on the long one.
    }

    // MARK: Fallback (not a real grid table)

    @Test("returns nil when there is no separator row")
    func noSeparator() {
        #expect(MarkdownTable.parse("| a | b |\n| 1 | 2 |\n") == nil)   // line 2 isn't `|---|`
        #expect(MarkdownTable.parse("| just one line |\n") == nil)       // single line
        #expect(MarkdownTable.parse("| a | b |\n| x | y |\n|---|---|\n") == nil) // separator not line 2
        // DISCRIMINATION: fails if any `|`-containing block is force-parsed as a grid — the caller
        // relies on nil to fall back to the pragmatic mono styling.
    }

    @Test("a separator with stray colons in the middle is rejected")
    func malformedSeparatorRejected() {
        #expect(MarkdownTable.parse("| a | b |\n| :-:- | --- |\n") == nil)
        // DISCRIMINATION: fails if the separator check only looks for dashes and ignores colon
        // placement, mis-classifying prose-with-pipes as a table.
    }

    @Test("a separator whose column count differs from the header is rejected")
    func mismatchedColumnCount() {
        #expect(MarkdownTable.parse("| a | b | c |\n|---|---|\n| 1 | 2 | 3 |\n") == nil)   // 3 header, 2 sep
        #expect(MarkdownTable.parse("| a | b |\n|---|---|---|\n| 1 | 2 |\n") == nil)        // 2 header, 3 sep
        // DISCRIMINATION: fails if header/separator column counts aren't required to agree — GFM
        // rejects the mismatch, and without this a lopsided block renders as a garbage grid.
    }

    @Test("a block whose first line is itself a separator is not a table")
    func separatorFirstLineRejected() {
        #expect(MarkdownTable.parse("|---|---|\n|---|---|\n| 1 | 2 |\n") == nil)
        // DISCRIMINATION: fails if the header line isn't screened for being a separator — the `|---|`
        // would masquerade as a header row with cell text "---".
    }

    @Test("a degenerate all-pipes / empty row is rejected, not a phantom empty column")
    func degeneratePipeRowRejected() {
        #expect(MarkdownTable.parse("|\n|---|\n") == nil)     // bare pipe header
        #expect(MarkdownTable.parse("||\n|---|\n") == nil)    // two-pipe empty header
        // DISCRIMINATION: fails if splitRow emits a phantom empty cell for a content-free row — such a
        // block groups as a `.table` (isTableRow passes for `|`) and would render an empty-header grid.
    }

    @Test("a header + separator with no data rows yields an empty rows list")
    func headerOnlyNoDataRows() {
        let t = try! #require(MarkdownTable.parse("| a | b |\n|---|---|\n"))
        #expect(t.columnCount == 2)
        #expect(t.rows.isEmpty)
        // DISCRIMINATION: fails if the trailing (blank) line past the final terminator is mistaken for
        // an empty data row, or if a header-only table is rejected.
    }

    @Test("a table at EOF with no trailing newline still addresses its cells")
    func noTrailingNewline() {
        let src = "| a | b |\n|---|---|\n| 1 | 2 |"   // deliberately no final \n
        let t = try! #require(MarkdownTable.parse(src))
        let ns = src as NSString
        #expect(ns.substring(with: t.rows[0][0].range) == "1")
        #expect(ns.substring(with: t.rows[0][1].range) == "2")
        // DISCRIMINATION: fails if line scanning assumes a terminating newline and drops or mis-ranges
        // the last row.
    }

    // MARK: Byte fidelity of cell ranges

    @Test("cell ranges are block-relative and address the exact source cell content")
    func cellRangesAddressSource() {
        let src = "| Name | Age |\n| --- | --- |\n| Ada | 36 |\n"
        let t = try! #require(MarkdownTable.parse(src))
        let ns = src as NSString
        #expect(ns.substring(with: t.header[0].range) == "Name")
        #expect(ns.substring(with: t.header[1].range) == "Age")
        #expect(ns.substring(with: t.rows[0][0].range) == "Ada")
        #expect(ns.substring(with: t.rows[0][1].range) == "36")
        // Every range is in bounds.
        let all = [t.header, t.rows.flatMap { $0 }].flatMap { $0 }
        for cell in all { #expect(NSMaxRange(cell.range) <= ns.length) }
        // DISCRIMINATION: an off-by-one in the pipe/space accounting would slice "Nam"/" Name"/etc.
    }

    // MARK: Integration with the block parser

    @Test("feeds a MarkdownParser .table block and cell ranges land in the full document")
    func integratesWithBlockParser() {
        let doc = "# H\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        let parsed = MarkdownParser.parse(doc)
        let tableBlock = try! #require(parsed.blocks.first { $0.kind == .table })
        let model = try! #require(MarkdownTable.parse(tableBlock.text))
        #expect(model.header.map(\.text) == ["a", "b"])
        // Block-relative + block origin == an absolute document range addressing the same cell.
        let ns = doc as NSString
        let cell = model.rows[0][1]                          // "2"
        let absolute = NSRange(location: tableBlock.range.location + cell.range.location, length: cell.range.length)
        #expect(ns.substring(with: absolute) == "2")
        // DISCRIMINATION: proves the block-relative contract the render + write-back rely on; fails
        // if the model returns document-absolute or otherwise mis-based ranges.
    }
}
