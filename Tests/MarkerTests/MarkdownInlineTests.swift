import Testing
import Foundation
@testable import Marker

@Suite("Markdown inline")
struct MarkdownInlineTests {
    private func spans(_ s: String) -> [InlineSpan] { MarkdownInline.spans(in: s) }
    private func content(_ s: String, _ span: InlineSpan) -> String { (s as NSString).substring(with: span.contentRange) }

    @Test("strong / emphasis / code / link detected with correct content")
    func basics() {
        let s1 = "a **bold** b"
        #expect(spans(s1).count == 1)
        #expect(spans(s1).first?.kind == .strong)
        #expect(content(s1, spans(s1).first!) == "bold")

        let s2 = "x *em* y"
        #expect(spans(s2).first?.kind == .emphasis)
        #expect(content(s2, spans(s2).first!) == "em")

        let s3 = "use `code` here"
        #expect(spans(s3).first?.kind == .code)
        #expect(content(s3, spans(s3).first!) == "code")

        let s4 = "see [text](http://u)"
        let link = try! #require(spans(s4).first)
        #expect(link.kind == .link)
        #expect(content(s4, link) == "text")
        #expect(link.markerRanges.count == 2)   // "[" before, "](http://u)" after
    }

    @Test("strikethrough (~~) and highlight (==) are detected with their content + markers")
    func strikeAndHighlight() {
        let s1 = "a ~~gone~~ b"
        let strike = try! #require(spans(s1).first)
        #expect(strike.kind == .strikethrough)
        #expect(content(s1, strike) == "gone")
        #expect(strike.markerRanges.count == 2)        // "~~" before + after

        let s2 = "a ==lit== b"
        let hi = try! #require(spans(s2).first)
        #expect(hi.kind == .highlight)
        #expect(content(s2, hi) == "lit")
        #expect(hi.markerRanges.count == 2)            // "==" before + after

        // Adjacent strike + highlight: two non-overlapping spans, sorted by position.
        let s4 = "~~a~~ ==b=="
        #expect(spans(s4).map(\.kind) == [.strikethrough, .highlight])

        // Code still claims first: ~~ inside a code span isn't a strike.
        let s3 = "`a~~b~~c`"
        #expect(spans(s3).count == 1)
        #expect(spans(s3).first?.kind == .code)
        // DISCRIMINATION: fails if ~~/== aren't scanned, or if they override a literal code span.
    }

    @Test("code claims first — a * inside code is not emphasis")
    func codeWins() {
        let s = "`a*b*c`"
        #expect(spans(s).count == 1)
        #expect(spans(s).first?.kind == .code)
        // DISCRIMINATION: fails if emphasis matches inside the literal code span (overlap not prevented).
    }

    @Test("multiple spans are non-overlapping and sorted by position")
    func multiple() {
        let result = spans("**a** *b* `c`")
        #expect(result.map(\.kind) == [.strong, .emphasis, .code])
        var cursor = -1
        for span in result {
            #expect(span.contentRange.location > cursor)
            cursor = span.contentRange.location
        }
        // DISCRIMINATION: fails if spans overlap or come back out of order.
    }

    @Test("** is one strong span, not two emphases")
    func strongNotEmphasis() {
        #expect(spans("**x**").count == 1)
        #expect(spans("**x**").first?.kind == .strong)
    }

    @Test("intraword underscores in snake_case do NOT italicize")
    func snakeCaseNoEmphasis() {
        #expect(spans("read_time_minutes").isEmpty)
        #expect(spans("a_b_c_d").isEmpty)
        #expect(spans("_a_b_").isEmpty)       // intentional (and CommonMark-faithful here) — pins the known limit
        #expect(spans("1_000_000").isEmpty)   // numeric underscores never italicize (digits are word chars)
        // A real `_emphasis_` (flanked by non-word chars) still works alongside snake_case.
        let mixed = "set read_time then _go_ now"
        let ems = spans(mixed)
        #expect(ems.count == 1)
        #expect(ems.first?.kind == .emphasis)
        #expect(content(mixed, ems.first!) == "go")
        // DISCRIMINATION: fails if `_` italicizes the interior of read_time_minutes (the dogfood bug),
        // or if the intraword guard is so strict it kills a legit _go_.
    }

    @Test("underscore emphasis works at word boundaries (start / end / spaced)")
    func underscoreEmphasisBoundaries() {
        #expect(content("_lead_ word", spans("_lead_ word").first!) == "lead")
        #expect(content("word _tail_", spans("word _tail_").first!) == "tail")
        // `*` keeps intraword emphasis (CommonMark asymmetry) — not guarded like `_`.
        #expect(spans("5*6*7").first?.kind == .emphasis)
    }

    // MARK: - MF1 inline completeness

    @Test("*** and ___ are bold+italic (strongEmphasis), not ** + a stray delimiter")
    func boldItalic() {
        let a = "a ***both*** b"
        #expect(spans(a).count == 1)
        #expect(spans(a).first?.kind == .strongEmphasis)
        #expect(content(a, spans(a).first!) == "both")

        let u = "a ___both___ b"
        #expect(spans(u).count == 1)
        #expect(spans(u).first?.kind == .strongEmphasis)
        #expect(content(u, spans(u).first!) == "both")
        // DISCRIMINATION: fails if *** is grabbed as **both** + a dangling *, or ___ as __ + _.
    }

    @Test("emphasis levels don't cannibalize each other: ** stays strong, * stays emphasis")
    func emphasisLevels() {
        #expect(spans("**b**").first?.kind == .strong)         // ** still bold with *** present
        #expect(spans("*i*").first?.kind == .emphasis)         // * still italic
        #expect(spans("***bi***").first?.kind == .strongEmphasis)
    }

    @Test("__ is bold, _ is italic; intraword double underscore never bolds")
    func underscoreLevels() {
        let b = "a __bold__ b"
        #expect(spans(b).first?.kind == .strong)
        #expect(content(b, spans(b).first!) == "bold")
        #expect(spans("a _em_ b").first?.kind == .emphasis)
        #expect(spans("a__b__c").isEmpty)   // snake-ish: __ flanked by word chars, guarded
        // DISCRIMINATION: fails if __ isn't recognized as bold, or if a__b__c bolds (snake_case bug).
    }

    @Test("autolinks: <url> and bare http(s) URLs become links; trailing punctuation isn't swallowed")
    func autolinks() {
        let angle = "see <https://example.com> now"
        let a = try! #require(spans(angle).first)
        #expect(a.kind == .link)
        #expect(content(angle, a) == "https://example.com")
        #expect(a.markerRanges.count == 2)          // the < and the >

        let bare = "go https://example.com/path today"
        let b = try! #require(spans(bare).first)
        #expect(b.kind == .link)
        #expect(content(bare, b) == "https://example.com/path")
        #expect(b.markerRanges.isEmpty)             // a bare URL has no scaffolding

        #expect(content("at https://example.com. end", spans("at https://example.com. end").first!) == "https://example.com")

        // A URL immediately followed by a markdown delimiter stops before it (no over-swallow).
        let adj = "x https://ex.com**bold** y"
        #expect(spans(adj).map(\.kind) == [.link, .strong])
        #expect(content(adj, spans(adj).first!) == "https://ex.com")
        // DISCRIMINATION: fails if a bare URL isn't linked, swallows the trailing period, eats an
        // adjacent **bold**, or the angle-autolink markers aren't captured.
    }

    @Test("a URL's underscores don't get emphasized (higher-priority link claims the whole range)")
    func urlDelimitersInert() {
        // Underscores are common in URL paths and stay part of the link (it claims before emphasis).
        let s = "see https://ex.com/a_b_c/read_me end"
        let sp = spans(s)
        #expect(sp.count == 1)
        #expect(sp.first?.kind == .link)
        #expect(content(s, sp.first!) == "https://ex.com/a_b_c/read_me")
        // DISCRIMINATION: fails if emphasis nibbles _b_ out of the URL (autolink must claim first).
        // NB: a literal `*` intentionally ENDS a bare URL (so an adjacent **bold** isn't swallowed —
        // see `autolinks()`); `*` is rare in real URLs, unlike `_`.
    }

    @Test("an escaped delimiter doesn't open a span — but an escaped char INSIDE a span keeps the span")
    func escapes() {
        // \*…\* must NOT italicize; the escape is role-suppression only, so it produces no span at all.
        #expect(spans("a \\*literal\\* b").isEmpty)

        // The escape must NOT break an ENCLOSING span — the escaped char is just literal content.
        let bold = "**foo\\_bar**"
        #expect(spans(bold).first?.kind == .strong)
        #expect(content(bold, spans(bold).first!) == "foo\\_bar")

        let code = "`a\\*b`"
        #expect(spans(code).count == 1)
        #expect(spans(code).first?.kind == .code)        // backslash literal inside code; span intact

        let link = "[read\\_me](u)"
        #expect(spans(link).first?.kind == .link)
        #expect(content(link, spans(link).first!) == "read\\_me")

        // A backslash before a non-delimiter (a Windows path) is inert.
        #expect(spans("C:\\Users").isEmpty)
        // DISCRIMINATION: fails if \* still opens emphasis, OR (the audit's bug) if the escape CLAIMS
        // bytes and kills the enclosing **strong** / `code` / [link] span.
    }

    @Test("emphasis doesn't open on a blank run")
    func noBlankEmphasis() {
        #expect(spans("a _ _ b").isEmpty)      // _ _  → blank content, skipped
        #expect(spans("a * * b").isEmpty)      // * *  → blank content, skipped
        #expect(spans("x ** ** y").isEmpty)    // ** ** → blank content, skipped
        // DISCRIMINATION: fails if a lone space between delimiters emphasizes (CommonMark forbids it).
    }

    @Test("images: ![alt](url) is one .image span with alt content + captured url, claimed before links")
    func images() {
        let s = "before ![a cat](img/cat.png) after"
        let sp = spans(s)
        #expect(sp.count == 1)
        let img = try! #require(sp.first)
        #expect(img.kind == .image)
        #expect(content(s, img) == "a cat")                                             // alt text
        let dest = try! #require(img.destinationRange)
        #expect((s as NSString).substring(with: dest) == "img/cat.png")                 // url captured
        #expect(img.markerRanges.count == 2)                                            // "![" + "](…)"

        // The image pattern claims BEFORE links — no stray literal `!` + a link span.
        #expect(spans("![pic](p.png) and [text](u)").map(\.kind) == [.image, .link])
        // A plain link is still a link (no destinationRange needed for it here).
        #expect(spans("[text](u)").first?.kind == .link)

        // Empty alt is common (`![](p.png)`) and still an image (alt group is zero-or-more).
        let noAlt = try! #require(spans("![](logo.png)").first)
        #expect(noAlt.kind == .image)
        #expect(("![](logo.png)" as NSString).substring(with: noAlt.destinationRange!) == "logo.png")
        // DISCRIMINATION: fails if ![..](..) parses as literal `!` + .link (kind wrong, `!` left over),
        // if the url isn't captured in destinationRange, or if an empty-alt image is missed.
    }

    @Test("soleImageSpan: a lone ![alt](url) line is a block image; image-in-text is not")
    func soleImage() {
        #expect(MarkdownInline.soleImageURL(in: "![a](pic.png)") == "pic.png")
        #expect(MarkdownInline.soleImageURL(in: "   ![a](pic.png)  ") == "pic.png")   // surrounding ws ok
        #expect(MarkdownInline.soleImageSpan(in: "look ![a](pic.png) here") == nil)   // inline-in-text → raw
        #expect(MarkdownInline.soleImageSpan(in: "just text") == nil)
        #expect(MarkdownInline.soleImageSpan(in: "![a](p.png) ![b](q.png)") == nil)  // two → not sole
        #expect(MarkdownInline.soleImageSpan(in: "![a](x.png)\ncaption") == nil)     // merged img+text para → raw
        #expect(MarkdownInline.soleImageURL(in: "![](logo.png)") == "logo.png")      // empty alt still a block image
        // DISCRIMINATION: fails if an inline-in-text image is treated as a block image (would replace the
        // surrounding words with a bare picture), or if surrounding whitespace defeats detection.
    }
}
