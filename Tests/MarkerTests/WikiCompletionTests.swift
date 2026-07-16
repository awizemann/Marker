import Testing
import Foundation
@testable import Marker

private func caret(_ at: Int) -> NSRange { NSRange(location: at, length: 0) }

/// The completion context at a caret, or nil when completion must not trigger.
private func context(_ text: String, _ at: Int) -> (query: String, replaceRange: NSRange)? {
    EditorCommands.wikiCompletionContext(in: text, selection: caret(at))
}

/// Accept `target` against the context computed at `at`, returning the resulting text + caret.
private func accept(_ target: String, in text: String, at: Int) -> (text: String, sel: NSRange)? {
    guard let ctx = context(text, at) else { return nil }
    let edit = EditorCommands.wikiCompletionAccept(target: target, replacing: ctx.replaceRange)
    let ns = NSMutableString(string: text)
    ns.replaceCharacters(in: edit.range, with: edit.replacement)
    return (ns as String, edit.selectionAfter)
}

@Suite("Wiki-link completion — trigger detection + insertion math")
struct WikiCompletionTests {

    // MARK: Trigger

    @Test("caret right after [[ triggers with an empty query")
    func emptyQueryAfterOpener() {
        let text = "see [["
        let ctx = context(text, 6)
        #expect(ctx?.query == "")
        #expect(ctx?.replaceRange == NSRange(location: 6, length: 0))
        // DISCRIMINATION: fails if `[[` alone doesn't open a session or the range points at the markers.
    }

    @Test("caret inside an unclosed [[ yields the partial query between [[ and the caret")
    func partialQuery() {
        let text = "see [[Renov"
        let ctx = context(text, 11)
        #expect(ctx?.query == "Renov")
        #expect(ctx?.replaceRange == NSRange(location: 6, length: 5))
    }

    @Test("caret mid-query only includes text BEFORE the caret")
    func caretMidQuery() {
        let ctx = context("see [[Renov", 8)   // caret after "Re"
        #expect(ctx?.query == "Re")
        #expect(ctx?.replaceRange == NSRange(location: 6, length: 2))
    }

    @Test("no [[ before the caret → no trigger")
    func noOpener() {
        #expect(context("plain text", 5) == nil)
        #expect(context("one [ bracket", 6) == nil)
    }

    @Test("a single [ is not an opener")
    func singleBracket() {
        #expect(context("[x", 2) == nil)
    }

    @Test("trigger dies once the link closes (caret after ]] )")
    func closedBeforeCaret() {
        let text = "see [[Home]] then"
        #expect(context(text, 12) == nil)   // right after ]]
        #expect(context(text, 15) == nil)   // further on
    }

    @Test("caret INSIDE a closed [[…]] does not trigger (editing ≠ completing)")
    func insideClosedLink() {
        let text = "see [[Home]] then"
        #expect(context(text, 8) == nil)    // between [[ and ]]
        #expect(context(text, 11) == nil)   // just before ]]
    }

    @Test("a second, unclosed [[ after a closed link triggers on ITS query")
    func secondLinkOnLine() {
        let text = "[[Home]] and [[Ren"
        let ctx = context(text, 18)
        #expect(ctx?.query == "Ren")
        #expect(ctx?.replaceRange == NSRange(location: 15, length: 3))
    }

    @Test("a later ]] belonging to a DIFFERENT link doesn't kill an unclosed [[ before it")
    func laterClosedLinkDoesNotKill() {
        let text = "[[Ren and [[Home]]"
        // Caret after "[[Ren" — the `]]` later on the line closes `[[Home`, not this opener.
        let ctx = context(text, 5)
        #expect(ctx?.query == "Ren")
    }

    @Test("trigger dies when the caret leaves the [[ range (before it / another line)")
    func caretLeavesRange() {
        let text = "see [[Ren\nnext line"
        #expect(context(text, 4) != nil ? false : true)   // before the [[ — no opener behind the caret
        #expect(context(text, 14) == nil)                  // on the next line — opener is on a previous line
        #expect(context(text, 9)?.query == "Ren")          // still at the end of the [[ line
    }

    @Test("a selection (not a caret) never triggers")
    func selectionNeverTriggers() {
        let sel = NSRange(location: 6, length: 3)
        #expect(EditorCommands.wikiCompletionContext(in: "see [[Ren", selection: sel) == nil)
    }

    @Test("no trigger inside an inline code span")
    func insideCodeSpan() {
        #expect(context("use `x [[Ren` here", 12) == nil)
        // A [[ AFTER the code span still triggers.
        let ctx = context("`code` then [[Ren", 17)
        #expect(ctx?.query == "Ren")
    }

    @Test("no trigger inside a fenced code block")
    func insideCodeFence() {
        let text = "```\nlet a = [[Ren\n```\n"
        let caretAt = ("```\nlet a = [[Ren" as NSString).length
        #expect(context(text, caretAt) == nil)
    }

    @Test("out-of-bounds / edge selections are refused, empty doc included")
    func bounds() {
        #expect(context("", 0) == nil)
        #expect(context("[[", 99) == nil)
        #expect(EditorCommands.wikiCompletionContext(in: "[[", selection: NSRange(location: -1, length: 0)) == nil)
        #expect(context("[[", 2)?.query == "")   // caret at doc end right after [[
    }

    @Test("passing the current parse gives the same answer as parsing internally")
    func documentParameterEquivalent() {
        let text = "```\n[[Ren\n```\nsee [[Ho"
        let doc = MarkdownParser.parse(text)
        let at = (text as NSString).length
        let a = EditorCommands.wikiCompletionContext(in: text, selection: caret(at))
        let b = EditorCommands.wikiCompletionContext(in: text, selection: caret(at), document: doc)
        #expect(a?.query == "Ho")
        #expect(a?.query == b?.query)
        #expect(a?.replaceRange == b?.replaceRange)
    }

    // MARK: Accept (insertion math)

    @Test("accept replaces the partial query with Target]] and lands the caret after the ]]")
    func acceptReplacesQuery() {
        let r = accept("Renovation", in: "see [[Renov", at: 11)
        #expect(r?.text == "see [[Renovation]]")
        #expect(r?.sel == caret(18))   // just past the ]]
        // DISCRIMINATION: fails if the opener is doubled ([[[[), the query survives, or the caret
        // lands inside the brackets.
    }

    @Test("accept on an empty query right after [[ completes the whole link")
    func acceptEmptyQuery() {
        let r = accept("Home", in: "see [[", at: 6)
        #expect(r?.text == "see [[Home]]")
        #expect(r?.sel == caret(12))
    }

    @Test("accept mid-line replaces only the partial query and keeps the tail")
    func acceptMidLine() {
        // Caret after "Re" with " tail" beyond it — only "Re" is replaced; the tail survives.
        let r = accept("Renovation", in: "see [[Re tail", at: 8)
        #expect(r?.text == "see [[Renovation]] tail")
        #expect(r?.sel == caret(18))
    }

    @Test("the accepted text parses as a real wiki-link span")
    func acceptedParsesAsWikiLink() {
        let r = accept("Home", in: "go [[Ho", at: 7)
        let spans = MarkdownInline.spans(in: r?.text ?? "")
        #expect(spans.contains { $0.kind == .wikiLink })
    }
}
