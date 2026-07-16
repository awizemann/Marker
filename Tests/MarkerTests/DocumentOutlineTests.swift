import Testing
import Foundation
@testable import Marker

@Suite("DocumentOutline — heading outline derivation")
struct DocumentOutlineTests {

    private func doc(_ s: String) -> MarkdownDocument { MarkdownParser.parse(s) }

    @Test("headings returns only heading blocks, in source order, with level + stripped title + range")
    func headingsBasic() {
        let src = "# Title\n\nintro para\n\n## Section A\n\nbody\n\n### Sub\n"
        let hs = DocumentOutline.headings(of: doc(src))
        #expect(hs.map(\.level) == [1, 2, 3])
        #expect(hs.map(\.title) == ["Title", "Section A", "Sub"])

        let ns = src as NSString
        #expect(hs[0].range.location == ns.range(of: "# Title").location)
        #expect(hs[1].range.location == ns.range(of: "## Section A").location)
        #expect(hs[2].range.location == ns.range(of: "### Sub").location)
        // DISCRIMINATION: fails if paragraphs leak in, the order is wrong, levels are miscounted, or the
        // ranges don't map to the actual heading lines (breaking click-to-scroll).
    }

    @Test("title stripping drops the marker run + surrounding whitespace but keeps inner text")
    func titleStripping() {
        #expect(DocumentOutline.title(from: "##   Spaced   \n") == "Spaced")
        #expect(DocumentOutline.title(from: "###### deep\n") == "deep")
        #expect(DocumentOutline.title(from: "  ## indented\n") == "indented")   // ≤3 leading spaces still a heading
        #expect(DocumentOutline.title(from: "# C# and F#\n") == "C# and F#")    // inner/trailing '#' preserved
        #expect(DocumentOutline.title(from: "###\n") == "")                     // bare marker → empty title
        // DISCRIMINATION: fails if it strips inner '#'s (mangling "C#" → "C"), leaves the leading
        // markers in, or over-trims a real title to nothing.
    }

    @Test("a document with no headings yields an empty outline (no fabricated structure)")
    func noHeadings() {
        #expect(DocumentOutline.headings(of: doc("just a paragraph\n\nand another\n")).isEmpty)
        // DISCRIMINATION: fails if non-heading blocks are surfaced as headings.
    }

    @Test("activeHeadingID is the last heading starting at/before the caret; nil before the first")
    func activeHeading() {
        let src = "intro\n\n# One\n\naaa\n\n## Two\n\nbbb\n"
        let hs = DocumentOutline.headings(of: doc(src))
        let ns = src as NSString
        let oneStart = ns.range(of: "# One").location
        let twoStart = ns.range(of: "## Two").location

        #expect(DocumentOutline.activeHeadingID(in: hs, caret: 0) == nil)                  // before any heading
        #expect(DocumentOutline.activeHeadingID(in: hs, caret: oneStart) == hs[0].id)      // exactly at "One"
        #expect(DocumentOutline.activeHeadingID(in: hs, caret: oneStart + 3) == hs[0].id)  // inside One's line
        #expect(DocumentOutline.activeHeadingID(in: hs, caret: twoStart - 1) == hs[0].id)  // still in One's section
        #expect(DocumentOutline.activeHeadingID(in: hs, caret: twoStart) == hs[1].id)      // at "Two"
        #expect(DocumentOutline.activeHeadingID(in: hs, caret: ns.length) == hs[1].id)     // EOF → last section
        // DISCRIMINATION: fails if the active section is off-by-one (highlights the NEXT heading), or
        // doesn't fall back to "caret before the first heading = nothing active".
    }

    @Test("an empty outline has no active heading")
    func activeEmpty() {
        #expect(DocumentOutline.activeHeadingID(in: [], caret: 0) == nil)
    }
}
