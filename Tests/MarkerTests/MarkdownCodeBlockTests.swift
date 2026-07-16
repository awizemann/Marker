import Testing
import Foundation
@testable import Marker

@Suite("Markdown code-block content")
struct MarkdownCodeBlockTests {

    @Test("content range excludes the opening (with language) and closing fence lines")
    func stripsFences() {
        let block = "```swift\nlet x = 1\nlet y = 2\n```\n"
        let range = try! #require(MarkdownCodeBlock.contentRange(inBlockText: block))
        #expect((block as NSString).substring(with: range) == "let x = 1\nlet y = 2\n")
        #expect(MarkdownCodeBlock.codeText(inBlockText: block) == "let x = 1\nlet y = 2")
        // DISCRIMINATION: fails if the language token line or the closing ``` leak into the code (the
        // copy would include "```swift" / "```"), or if an off-by-one clips the first/last code line.
    }

    @Test("tilde fences and a trailing-newline-less block both work")
    func tildeAndNoTrailingNewline() {
        #expect(MarkdownCodeBlock.codeText(inBlockText: "~~~\necho hi\n~~~\n") == "echo hi")
        #expect(MarkdownCodeBlock.codeText(inBlockText: "```\na\nb\n```") == "a\nb")   // no final newline
    }

    @Test("an unterminated fence takes code to the end of the block")
    func unterminated() {
        // The parser hands us an unterminated fence as one block with no closing ```.
        #expect(MarkdownCodeBlock.codeText(inBlockText: "```js\nconst x = 1\n") == "const x = 1")
    }

    @Test("an empty code block (fences only) has no code body")
    func emptyBody() {
        #expect(MarkdownCodeBlock.contentRange(inBlockText: "```\n```\n") == nil)
        #expect(MarkdownCodeBlock.codeText(inBlockText: "```\n```\n") == nil)
        #expect(MarkdownCodeBlock.contentRange(inBlockText: "```swift\n") == nil)   // opener only
        // DISCRIMINATION: fails if an empty block yields a bogus zero/negative range (a copy of "" or a
        // crash), instead of nil so the caller shows no button / leaves styling alone.
    }

    @Test("blank lines inside the code are preserved (only trailing newlines trimmed)")
    func preservesInteriorBlanks() {
        let block = "```\nline1\n\nline3\n\n```\n"
        #expect(MarkdownCodeBlock.codeText(inBlockText: block) == "line1\n\nline3")
        // DISCRIMINATION: fails if trimming eats interior blank lines, or leaves the trailing blank.
    }
}
