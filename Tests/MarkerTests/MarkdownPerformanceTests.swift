import Testing
import Foundation
@testable import Marker

/// P1.4 latency gate. The editor reparses on every keystroke (P1.2's naive full reparse), so
/// parse() time IS the per-keystroke cost floor. These measure it at scale to confirm the approach
/// is viable (linear, fast) — the budgets are GENEROUS so they catch an accidental O(n²), not the
/// machine's mood (timing assertions are otherwise brittle; see testing conventions).
@Suite("Markdown performance")
struct MarkdownPerformanceTests {

    /// ~6,000 lines of mixed markdown (headings, inline-rich paragraphs, lists, quotes, fences).
    private func bigDocument() -> String {
        let unit = """
        # Heading

        Some **bold** and *italic* and `code` and a [link](http://x) in a paragraph that runs on.

        - a list item with `code`
        - another **item**

        > a soft quote

        ```swift
        let x = 1
        ```


        """
        return String(repeating: unit, count: 500)
    }

    @Test("parsing ~6k lines stays linear and well under a keystroke budget")
    func parseLargeDocument() {
        let big = bigDocument()
        let clock = ContinuousClock()
        var doc: MarkdownDocument?
        let elapsed = clock.measure { doc = MarkdownParser.parse(big) }
        let parsed = doc!

        // Fidelity holds at scale.
        #expect(parsed.blocks.map(\.text).joined() == big)
        print("[perf] parse(\(parsed.blocks.count) blocks / \((big as NSString).length) chars) = \(elapsed)")
        // Generous bound: real parse is single-digit ms; this only fires on an algorithmic regression.
        #expect(elapsed < .milliseconds(400), "parse took \(elapsed) — possible O(n^2) regression")
    }

    @Test("inline scanning a large paragraph is bounded")
    func inlineScanLargeParagraph() {
        let para = String(repeating: "word **bold** more *em* and `code` and [a](b) text. ", count: 1000)
        let clock = ContinuousClock()
        var spans: [InlineSpan] = []
        let elapsed = clock.measure { spans = MarkdownInline.spans(in: para) }
        print("[perf] inline(\(spans.count) spans / \((para as NSString).length) chars) = \(elapsed)")
        #expect(elapsed < .milliseconds(400), "inline scan took \(elapsed)")
    }
}
