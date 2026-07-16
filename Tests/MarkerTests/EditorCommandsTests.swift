import Testing
import Foundation
@testable import Marker

/// Apply a command's edit to `text` and return the resulting text + the selection it leaves. `nil` when
/// the command doesn't apply. Mirrors exactly what the NSTextView does: replace the range, then select.
private func applied(_ command: EditorCommand, to text: String, _ selection: NSRange) -> (text: String, sel: NSRange)? {
    guard let edit = EditorCommands.textEdit(for: command, in: text, selection: selection) else { return nil }
    let ns = NSMutableString(string: text)
    ns.replaceCharacters(in: edit.range, with: edit.replacement)
    return (ns as String, edit.selectionAfter)
}

private func caret(_ at: Int) -> NSRange { NSRange(location: at, length: 0) }

/// Apply a newline-continuation at a caret; nil when it doesn't apply (a plain newline should happen).
private func newline(_ text: String, _ at: Int) -> (text: String, sel: NSRange)? {
    guard let edit = EditorCommands.newlineContinuation(in: text, selection: caret(at)) else { return nil }
    let ns = NSMutableString(string: text)
    ns.replaceCharacters(in: edit.range, with: edit.replacement)
    return (ns as String, edit.selectionAfter)
}

@Suite("Editor commands — byte-precise mutations")
struct EditorCommandsTests {

    // MARK: Inline wrap / toggle

    @Test("bold on an empty caret inserts the pair with the caret between it")
    func boldEmptyCaret() {
        let r = applied(.bold, to: "hello world", caret(5))
        #expect(r?.text == "hello**** world")
        #expect(r?.sel == caret(7))
        // DISCRIMINATION: fails if it wraps the whole line, or leaves the caret outside the markers.
    }

    @Test("bold on a selection wraps it and keeps the inner content selected")
    func boldWrapsSelection() {
        let r = applied(.bold, to: "hello world", NSRange(location: 0, length: 5))
        #expect(r?.text == "**hello** world")
        #expect(r?.sel == NSRange(location: 2, length: 5))   // "hello" still selected → re-apply toggles off
    }

    @Test("bold toggles OFF when the selection IS the wrapped span")
    func boldTogglesOffInclusive() {
        let r = applied(.bold, to: "**hello** world", NSRange(location: 0, length: 9))
        #expect(r?.text == "hello world")
        #expect(r?.sel == NSRange(location: 0, length: 5))
    }

    @Test("bold toggles OFF when the markers sit just outside the selection")
    func boldTogglesOffExclusive() {
        let r = applied(.bold, to: "**hello** world", NSRange(location: 2, length: 5))
        #expect(r?.text == "hello world")
        #expect(r?.sel == NSRange(location: 0, length: 5))
        // DISCRIMINATION: round-trips boldWrapsSelection — wrap then toggle must return the original.
    }

    @Test("italic / code / strike / highlight wrap with their own delimiters")
    func otherWraps() {
        let sel = NSRange(location: 0, length: 1)
        #expect(applied(.italic, to: "x", sel)?.text == "*x*")
        #expect(applied(.inlineCode, to: "x", sel)?.text == "`x`")
        #expect(applied(.strikethrough, to: "x", sel)?.text == "~~x~~")
        #expect(applied(.highlight, to: "x", sel)?.text == "==x==")
    }

    // MARK: Headings (single line, toggle level)

    @Test("heading(1) on a plain line adds the prefix and shifts the caret by the prefix length")
    func headingAdds() {
        let r = applied(.heading(1), to: "hello", caret(2))   // caret was at "he|llo"
        #expect(r?.text == "# hello")
        #expect(r?.sel == caret(4))   // "# he|llo" — column preserved (shifted by the 2-char "# ")
    }

    @Test("heading(1) on an H2 line swaps to H1 (doesn't stack ###) and adjusts the caret")
    func headingSwapsLevel() {
        let r = applied(.heading(1), to: "## hello", caret(4))   // "## h|ello"
        #expect(r?.text == "# hello")
        #expect(r?.sel == caret(3))   // shifted left by 1 (## → #)
        // DISCRIMINATION: fails if it prepends to give "# ## hello", or mis-shifts the caret.
    }

    @Test("heading(1) on an H1 line toggles back to a paragraph")
    func headingTogglesOff() {
        let r = applied(.heading(1), to: "# hello", caret(3))   // "# h|ello"
        #expect(r?.text == "hello")
        #expect(r?.sel == caret(1))   // shifted left by the removed 2-char prefix
    }

    @Test("heading operates only on the caret's line in a multi-line doc")
    func headingMultiLine() {
        let r = applied(.heading(2), to: "a\nhello\nb", caret(4))   // caret inside "hello" (offset 4 = "hel|lo")
        #expect(r?.text == "a\n## hello\nb")
        #expect(r?.sel == caret(7))   // shifted right by the 3-char "## " within the second line
        // DISCRIMINATION: fails if it headings the whole selection span, the wrong line, or mis-offsets
        // the caret by the leading "a\n".
    }

    // MARK: Line-prefix block toggles

    @Test("bullet list prefixes every selected line (selection preserved), and toggles them all off")
    func bulletToggle() {
        let on = applied(.bulletList, to: "a\nb", NSRange(location: 0, length: 3))
        #expect(on?.text == "- a\n- b")
        #expect(on?.sel == NSRange(location: 0, length: 7))   // the rebuilt block stays selected
        let off = applied(.bulletList, to: "- a\n- b", NSRange(location: 0, length: 7))
        #expect(off?.text == "a\nb")
        #expect(off?.sel == NSRange(location: 0, length: 3))
    }

    @Test("ordered list numbers sequentially and round-trips off→on")
    func orderedNumbers() {
        let r = applied(.orderedList, to: "a\nb\nc", NSRange(location: 0, length: 5))
        #expect(r?.text == "1. a\n2. b\n3. c")
        #expect(r?.sel == NSRange(location: 0, length: 14))
        // toggle off, then back on, returns the original numbering
        let off = applied(.orderedList, to: "1. a\n2. b\n3. c", NSRange(location: 0, length: 14))
        #expect(off?.text == "a\nb\nc")
        let reOn = applied(.orderedList, to: "a\nb\nc", NSRange(location: 0, length: 5))
        #expect(reOn?.text == "1. a\n2. b\n3. c")
        // DISCRIMINATION: fails if every line becomes "1. ", or the off regex doesn't strip "N. ".
    }

    @Test("task list toggles on and off")
    func taskToggle() {
        let on = applied(.taskList, to: "a\nb", NSRange(location: 0, length: 3))
        #expect(on?.text == "- [ ] a\n- [ ] b")
        let off = applied(.taskList, to: "- [ ] a\n- [x] b", NSRange(location: 0, length: 15))
        #expect(off?.text == "a\nb")   // strips both [ ] and [x] forms
    }

    @Test("blockquote prefixes with > , toggles off, and leaves blank lines untouched")
    func quoteToggle() {
        let r = applied(.blockquote, to: "a\n\nb", NSRange(location: 0, length: 4))
        #expect(r?.text == "> a\n\n> b")          // blank middle line untouched
        let off = applied(.blockquote, to: "> a\n> b", NSRange(location: 0, length: 7))
        #expect(off?.text == "a\nb")
        // DISCRIMINATION: fails if it turns the blank line into "> ", or the quote toggle-off regex is wrong.
    }

    @Test("a list command on a MIXED-kind selection converts every line (no double-prefix, no syntax loss)")
    func listConvertsMixedKinds() {
        // a task line + an ordered line + a plain line → all become bullets, cleanly.
        let r = applied(.bulletList, to: "- [ ] task\n1. ordered\nplain", NSRange(location: 0, length: 26))
        #expect(r?.text == "- task\n- ordered\n- plain")
        // DISCRIMINATION: the old impl saw "- [ ] task" as already-bulleted (toggled it OFF to "[ ] task")
        // and double-prefixed the ordered line ("- 1. ordered"). This pins the convert semantics.
    }

    @Test("a line prefix on a bare caret operates on the caret's line")
    func prefixOnCaretLine() {
        let r = applied(.bulletList, to: "hello", caret(2))
        #expect(r?.text == "- hello")
    }

    // MARK: Inserts

    @Test("code block: empty caret drops a fence with the caret on the empty middle line")
    func codeBlockEmpty() {
        let r = applied(.codeBlock, to: "", caret(0))
        #expect(r?.text == "```\n\n```")
        #expect(r?.sel == caret(4))
    }

    @Test("code block: a selection is fenced")
    func codeBlockWrapsSelection() {
        let r = applied(.codeBlock, to: "let x = 1", NSRange(location: 0, length: 9))
        #expect(r?.text == "```\nlet x = 1\n```")
        #expect(r?.sel == NSRange(location: 4, length: 9))
    }

    @Test("both toolsets offer a Code block tool, distinct from inline code")
    func toolsetsOfferCodeBlock() {
        // The SELECTION palette must be able to turn a selection INTO a fenced code block — not only
        // inline `code` (single backticks), which on a multi-line selection produces broken markdown
        // (one giant single-backtick span that renders as plain text).
        #expect(EditorTool.selection.contains { $0.command == .codeBlock })
        #expect(EditorTool.cursor.contains { $0.command == .codeBlock })
        #expect(EditorTool.selection.contains { $0.command == .inlineCode })   // inline code stays separate
        // DISCRIMINATION: fails if the selection toolset lacks a code-block command — the exact reported
        // bug (a selected block of pasted code couldn't be turned into a real code block via ⌘K).
    }

    @Test("copyCodeBlock is a non-mutating action — it produces no text edit")
    func copyCodeBlockIsNotAnEdit() {
        #expect(applied(.copyCodeBlock, to: "```\ncode\n```", caret(5)) == nil)
        // DISCRIMINATION: fails if the copy action accidentally maps to a text mutation (it must be a
        // pure side effect the host routes to the clipboard, never an edit to the document).
    }

    @Test("table inserts a starter grid with the first header selected")
    func tableInsert() {
        let r = applied(.table, to: "", caret(0))
        #expect(r?.text == "| Column | Column |\n| --- | --- |\n| Cell | Cell |\n")
        #expect(r?.sel == NSRange(location: 2, length: 6))   // "Column" header selected
    }

    @Test("table inserts on its own line when the caret isn't at a line start")
    func tableInsertNeedsLineBreak() {
        let r = applied(.table, to: "text", caret(4))
        #expect(r?.text.hasPrefix("text\n| Column") == true)
        // DISCRIMINATION: fails if the table is jammed onto the end of "text".
    }

    @Test("turning a selection into a table NEVER deletes the selected text")
    func tableKeepsSelection() {
        let r = applied(.table, to: "keep me", NSRange(location: 0, length: 7))
        #expect(r?.text.hasPrefix("keep me\n| Column") == true)   // the selection survives, table follows
        // DISCRIMINATION: fails if "Turn selection into → Table" replaces (deletes) the user's prose.
    }

    @Test("link: empty caret inserts [text](url) with 'text' selected")
    func linkEmpty() {
        let r = applied(.link, to: "", caret(0))
        #expect(r?.text == "[text](url)")
        #expect(r?.sel == NSRange(location: 1, length: 4))
    }

    @Test("link: a selection becomes the label and 'url' is selected")
    func linkFromSelection() {
        let r = applied(.link, to: "click", NSRange(location: 0, length: 5))
        #expect(r?.text == "[click](url)")
        #expect(r?.sel == NSRange(location: 8, length: 3))   // "url" selected
    }

    @Test("frontmatter inserts a --- block at the top, but only when one isn't already present")
    func frontmatter() {
        let r = applied(.frontmatter, to: "# Title", caret(0))
        #expect(r?.text == "---\n\n---\n# Title")
        #expect(r?.sel == caret(4))
        #expect(applied(.frontmatter, to: "---\ntitle: x\n---", caret(0)) == nil)    // real frontmatter → no-op
        // A document that merely OPENS with a thematic break is NOT frontmatter (no closing fence) → insert.
        #expect(applied(.frontmatter, to: "---\n\nSome text", caret(0)) != nil)
        // DISCRIMINATION: the old guard (first 3 chars == "---") false-positived the thematic break and
        // refused to add frontmatter.
    }

    // MARK: Operate on the selected lines

    @Test("sort lines A→Z, preserving the trailing newline and selecting the result")
    func sortLines() {
        let r = applied(.sortLines, to: "banana\napple\ncherry\n", NSRange(location: 0, length: 20))
        #expect(r?.text == "apple\nbanana\ncherry\n")
        #expect(r?.sel == NSRange(location: 0, length: 19))   // 20 rebuilt − 1 trailing newline
    }

    @Test("sort WITHOUT a trailing newline keeps it absent")
    func sortNoTrailingNewline() {
        let r = applied(.sortLines, to: "b\na\nc", NSRange(location: 0, length: 5))
        #expect(r?.text == "a\nb\nc")          // no phantom trailing newline invented
        #expect(r?.sel == NSRange(location: 0, length: 5))
    }

    @Test("dedupe removes later duplicate lines, preserving first-seen order")
    func dedupeLines() {
        let r = applied(.dedupeLines, to: "a\nb\na\nc\nb\n", NSRange(location: 0, length: 10))
        #expect(r?.text == "a\nb\nc\n")
        #expect(r?.sel == NSRange(location: 0, length: 5))
    }

    @Test("title-case uppercases lowercase words but PRESERVES acronyms, camelCase, and contractions")
    func titleCaseLines() {
        let r = applied(.titleCaseLines, to: "hello world\nthe quick fox", NSRange(location: 0, length: 25))
        #expect(r?.text == "Hello World\nThe Quick Fox")

        // The real-content cases that .capitalized would mangle:
        #expect(applied(.titleCaseLines, to: "NASA report", NSRange(location: 0, length: 11))?.text == "NASA Report")
        #expect(applied(.titleCaseLines, to: "the iPhone app", NSRange(location: 0, length: 14))?.text == "The iPhone App")
        #expect(applied(.titleCaseLines, to: "don't stop", NSRange(location: 0, length: 10))?.text == "Don't Stop")
        // DISCRIMINATION: .capitalized would give "Nasa Report", "The Iphone App", "Don'T Stop" —
        // lossy mangling that would be SAVED into the user's file.
    }

    @Test("line ops require a selection — a bare caret is a no-op")
    func lineOpsNeedSelection() {
        #expect(applied(.sortLines, to: "a\nb", caret(0)) == nil)
        #expect(applied(.dedupeLines, to: "a\nb", caret(0)) == nil)
        // DISCRIMINATION: fails if a caret-only sort silently rewrites the whole document.
    }

    // MARK: UTF-16 / surrogate pairs

    @Test("bold-wrapping a selection that CONTAINS an emoji uses exact UTF-16 offsets")
    func boldWrapsEmoji() {
        // "a😀b": 😀 is 2 UTF-16 units, so it occupies offsets 1...2; "b" is at 3.
        let r = applied(.bold, to: "a😀b", NSRange(location: 1, length: 2))
        #expect(r?.text == "a**😀**b")
        #expect(r?.sel == NSRange(location: 3, length: 2))   // inner "😀" still selected (loc+2, len 2)
        // DISCRIMINATION: fails if the engine ever uses character (not UTF-16) offsets — emoji docs corrupt.
    }

    @Test("bold at a caret AFTER an emoji inserts at the right UTF-16 offset")
    func boldCaretAfterEmoji() {
        let r = applied(.bold, to: "😀x", caret(2))   // caret right after the 2-unit emoji
        #expect(r?.text == "😀****x")
        #expect(r?.sel == caret(4))
    }

    // MARK: Wrap interaction

    @Test("italic on the inner of a bold span makes it bold+italic, not italic-only (no bold loss)")
    func italicInsideBold() {
        let r = applied(.italic, to: "**bold**", NSRange(location: 2, length: 4))   // select "bold"
        #expect(r?.text == "***bold***")
        // DISCRIMINATION: the naive toggle-off stripped one * from each ** → "*bold*" (bold lost). The
        // single-char guard makes it wrap instead → bold+italic.
    }

    // MARK: Empty doc / end of doc

    @Test("commands on an empty document behave (wrap inserts the pair, heading adds the prefix)")
    func emptyDoc() {
        #expect(applied(.bold, to: "", caret(0))?.text == "****")
        #expect(applied(.heading(1), to: "", caret(0))?.text == "# ")
        #expect(applied(.bulletList, to: "", caret(0))?.text == "- ")
    }

    @Test("a line prefix at end-of-doc with no trailing newline works")
    func lastLineNoNewline() {
        let r = applied(.bulletList, to: "abc", caret(3))   // caret at EOF, no trailing \n
        #expect(r?.text == "- abc")
        #expect(r?.sel == NSRange(location: 0, length: 5))
        // DISCRIMINATION: lineRange(for:) at length is a sharp edge — fails if it drops/duplicates the line.
    }

    // MARK: Wrap trims trailing whitespace (the "italic broke it" bug)

    @Test("wrapping a selection that includes a trailing newline keeps the closing marker on the line")
    func wrapTrimsTrailingNewline() {
        let r = applied(.bold, to: "word\nmore", NSRange(location: 0, length: 5))   // selection "word\n"
        #expect(r?.text == "**word**\nmore")    // NOT "**word\n**more"
        #expect(r?.sel == NSRange(location: 2, length: 4))   // "word" still selected
        // DISCRIMINATION: the bug wrapped the newline too, splitting the closing ** onto the next line.
    }

    @Test("wrapping a selection with surrounding spaces leaves the spaces outside the markers")
    func wrapTrimsSpaces() {
        let r = applied(.bold, to: " word ", NSRange(location: 0, length: 6))
        #expect(r?.text == " **word** ")
        // DISCRIMINATION: fails if it produces "** word **" (which isn't valid bold in CommonMark).
    }

    // MARK: Newline continuation (Enter in a list / quote)

    @Test("Enter in a non-empty bullet continues the list")
    func continueBullet() {
        let r = newline("- item", 6)
        #expect(r?.text == "- item\n- ")
        #expect(r?.sel == caret(9))
    }

    @Test("Enter in an ordered item continues with the next number")
    func continueOrdered() {
        let r = newline("1. first", 8)
        #expect(r?.text == "1. first\n2. ")
        #expect(r?.sel == caret(12))
        // DISCRIMINATION: fails if it repeats "1. " instead of incrementing.
    }

    @Test("Enter in a task item continues with a fresh unchecked box")
    func continueTask() {
        let r = newline("- [x] done", 10)
        #expect(r?.text == "- [x] done\n- [ ] ")   // new item is unchecked, original keeps [x]
    }

    @Test("Enter in a blockquote continues the quote")
    func continueQuote() {
        let r = newline("> quoted", 8)
        #expect(r?.text == "> quoted\n> ")
    }

    @Test("indentation is preserved when continuing")
    func continueIndented() {
        let r = newline("  - item", 8)
        #expect(r?.text == "  - item\n  - ")
    }

    @Test("Enter on an EMPTY list item exits the list (strips the marker)")
    func exitEmptyItem() {
        #expect(newline("- ", 2)?.text == "")          // bullet
        #expect(newline("1. ", 3)?.text == "")          // ordered
        #expect(newline("- [ ] ", 6)?.text == "")       // task
        let exited = newline("- ", 2)
        #expect(exited?.sel == caret(0))
        // DISCRIMINATION: fails if an empty bullet + Enter keeps continuing forever instead of exiting.
    }

    @Test("Enter continues a list line MID-document, splitting at the caret")
    func continueMidDocument() {
        let r = newline("- a\n- b", 7)   // caret at end of "- b"
        #expect(r?.text == "- a\n- b\n- ")
        #expect(r?.sel == caret(10))
    }

    @Test("Enter on a plain paragraph is a no-op (the host does a normal newline)")
    func plainNewlineIsNil() {
        #expect(newline("hello", 5) == nil)
        #expect(EditorCommands.newlineContinuation(in: "- item", selection: NSRange(location: 0, length: 3)) == nil)  // a selection → nil
    }

    // MARK: Task checkbox toggle (click geometry)

    /// Apply a checkbox toggle at a clicked index; nil when the click misses the box cells.
    private func toggled(_ text: String, blockRange: NSRange? = nil, at location: Int) -> String? {
        let block = blockRange ?? NSRange(location: 0, length: (text as NSString).length)
        guard let edit = EditorCommands.taskCheckboxToggle(in: text, blockRange: block,
                                                           location: location, selection: caret(0)) else { return nil }
        let ns = NSMutableString(string: text)
        ns.replaceCharacters(in: edit.range, with: edit.replacement)
        return ns as String
    }

    @Test("a click inside [ ] checks the box; inside [x] unchecks it")
    func checkboxToggles() {
        // "- [ ] buy milk" — box cells are indices 2([)…5(just past ]).
        #expect(toggled("- [ ] buy milk", at: 3) == "- [x] buy milk")
        #expect(toggled("- [x] buy milk", at: 3) == "- [ ] buy milk")
        #expect(toggled("- [X] buy milk", at: 3) == "- [ ] buy milk")   // capital X counts as checked
        // Edges: the `[` cell and the insertion point just past `]` both count (insertion-point space).
        #expect(toggled("- [ ] t", at: 2) == "- [x] t")
        #expect(toggled("- [ ] t", at: 5) == "- [x] t")
    }

    @Test("a click outside the box cells is a no-op; indented and *-bulleted tasks still hit")
    func checkboxGeometry() {
        #expect(toggled("- [ ] buy milk", at: 0) == nil)    // on the bullet
        #expect(toggled("- [ ] buy milk", at: 8) == nil)    // in the body text
        #expect(toggled("- plain item", at: 3) == nil)      // not a task at all
        // Indented task: the box shifts right by the indent; the same interior click flips it.
        #expect(toggled("  - [ ] nested", at: 5) == "  - [x] nested")
        #expect(toggled("  - [ ] nested", at: 1) == nil)    // in the indent
        #expect(toggled("* [ ] star", at: 3) == "* [x] star")
        // The toggle keeps the caller's selection verbatim (1-for-1 swap; offsets don't shift).
        let edit = EditorCommands.taskCheckboxToggle(in: "- [ ] t", blockRange: NSRange(location: 0, length: 7),
                                                     location: 3, selection: NSRange(location: 6, length: 1))
        #expect(edit?.selectionAfter == NSRange(location: 6, length: 1))
        // DISCRIMINATION: fails if the geometry is off by one (body clicks toggling would make plain
        // clicks in a task's text destructive), or if indent/bullet variants miss.
    }

    @Test("checkbox toggle on a block mid-document uses absolute offsets")
    func checkboxMidDocument() {
        let text = "para\n- [ ] task\nafter"
        let block = NSRange(location: 5, length: 11)   // "- [ ] task\n"
        let edit = EditorCommands.taskCheckboxToggle(in: text, blockRange: block, location: 8, selection: caret(0))
        #expect(edit?.range == NSRange(location: 8, length: 1))
        #expect(edit?.replacement == "x")
        // A click at the same LOCAL offset but outside this block's cells → nil.
        #expect(EditorCommands.taskCheckboxToggle(in: text, blockRange: block, location: 12, selection: caret(0)) == nil)
    }

    // MARK: Safety

    @Test("an out-of-bounds selection is rejected, not crashed")
    func outOfBoundsRejected() {
        #expect(EditorCommands.textEdit(for: .bold, in: "hi", selection: NSRange(location: 5, length: 3)) == nil)
        #expect(EditorCommands.taskCheckboxToggle(in: "- [ ] t", blockRange: NSRange(location: 0, length: 99),
                                                  location: 3, selection: caret(0)) == nil)
    }
}
