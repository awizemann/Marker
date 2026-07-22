import Testing
import Foundation
@testable import Marker

@Suite("Markdown contentText — block markers stripped")
struct MarkdownContentTextTests {

    /// Parse `source` and return the contentText of every block (blanks included, for position).
    private func contents(_ source: String) -> [String] {
        MarkdownParser.parse(source).blocks.map(\.contentText)
    }

    @Test("headings lose their hashes, closing sequences included")
    func headings() {
        #expect(contents("# Title\n") == ["Title"])
        #expect(contents("### Deep One\n") == ["Deep One"])
        #expect(contents("## Closed ##\n") == ["Closed"])
        #expect(contents("## Trailing spaces   \n") == ["Trailing spaces"])
        #expect(contents("# Title#\n") == ["Title#"])           // no space → hash is content
        #expect(contents("#\n") == [""])                         // empty heading
    }

    @Test("list items lose marker and indent; task items lose the checkbox too")
    func listItems() {
        #expect(contents("- alpha\n") == ["alpha"])
        #expect(contents("* beta\n") == ["beta"])
        #expect(contents("+ gamma\n") == ["gamma"])
        #expect(contents("  - nested\n") == ["nested"])
        #expect(contents("1. one\n") == ["one"])
        #expect(contents("12) twelve\n") == ["twelve"])
        #expect(contents("- [ ] todo\n") == ["todo"])
        #expect(contents("- [x] done\n") == ["done"])
    }

    @Test("blockquotes lose the > prefix per line, keeping line structure")
    func blockquotes() {
        #expect(contents("> one\n> two\n") == ["one\ntwo"])
        #expect(contents(">bare\n") == ["bare"])
        #expect(contents("> \n") == [""])
    }

    @Test("code blocks return the interior verbatim, fences gone")
    func codeBlocks() {
        #expect(contents("```swift\nlet x = 1\nlet y = 2\n```\n") == ["let x = 1\nlet y = 2"])
        #expect(contents("```\n\n```\n") == [""])
        #expect(contents("```swift\nunterminated\n") == ["unterminated"])   // EOF closes
        #expect(contents("```\n") == [""])                                  // lone fence
        // Interior lines that LOOK like markdown stay verbatim.
        #expect(contents("```md\n# not a heading\n```\n") == ["# not a heading"])
    }

    @Test("paragraphs and tables only lose the trailing terminator")
    func paragraphsAndTables() {
        #expect(contents("plain line\n") == ["plain line"])
        #expect(contents("no trailing newline") == ["no trailing newline"])
        #expect(contents("two\nlines\n") == ["two\nlines"])                 // greedy paragraph
        #expect(contents("| a | b |\n|---|---|\n| 1 | 2 |\n") == ["| a | b |\n|---|---|\n| 1 | 2 |"])
    }

    @Test("blank and thematic-break content is empty")
    func structuralBlocks() {
        #expect(contents("\n") == [""])
        #expect(contents("---\n") == [""])
    }

    @Test("CRLF terminators are stripped like LF")
    func crlf() {
        #expect(contents("# Title\r\n") == ["Title"])
        #expect(contents("> q1\r\n> q2\r\n") == ["q1\nq2"])
        #expect(contents("```\r\ncode\r\n```\r\n") == ["code"])
    }
}
