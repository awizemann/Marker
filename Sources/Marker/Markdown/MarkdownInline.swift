//
//  MarkdownInline.swift
//  Marker — (ex TrapperKeeperCore) Markdown (P1.3)
//
//  Inline span scanner over a single block's text — finds strong/emphasis/code/link spans so the
//  editor can render the content (bold, italic, mono) while dimming the syntax markers. Like the
//  block parser, it only RECORDS ranges; it never alters the text.
//
//  Spike-level: fixed-delimiter scan with priority + overlap avoidance (code is literal so it claims
//  first; a `*` inside code won't become emphasis). Not CommonMark-complete (no escapes/nesting) —
//  good enough to prove the styling approach; hardened later.
//

import Foundation

public nonisolated enum InlineKind: Sendable, Equatable {
    case strong, emphasis, code, link, strikethrough, highlight
    /// `***x***` / `___x___` — bold AND italic.
    case strongEmphasis
    /// `![alt](url)` — an image reference. `contentRange` = the alt text; `destinationRange` = the url.
    case image
    /// `[[Target Name]]` — a wiki-style link. `contentRange` = the target text; the markers are the
    /// `[[` and `]]`. The consumer resolves the target (note title, file name, …) itself.
    case wikiLink
}

public nonisolated struct InlineSpan: Sendable, Equatable {
    public let kind: InlineKind
    /// The syntax-marker ranges to DIM (e.g. the `**`, the `` ` ``, the `[`…`](url)` scaffolding).
    public let markerRanges: [NSRange]
    /// The rendered content range (the text inside the markers).
    public let contentRange: NSRange
    /// The destination URL's range in the source, for a span that has one (`.image` today; links could
    /// adopt it later). nil when the span carries no destination.
    public let destinationRange: NSRange?

    public init(kind: InlineKind, markerRanges: [NSRange], contentRange: NSRange, destinationRange: NSRange? = nil) {
        self.kind = kind
        self.markerRanges = markerRanges
        self.contentRange = contentRange
        self.destinationRange = destinationRange
    }
}

public enum MarkdownInline {

    private struct Pattern { let kind: InlineKind; let regex: NSRegularExpression; let contentGroup: Int; let urlGroup: Int? }

    private static let patterns: [Pattern] = {
        func make(_ kind: InlineKind, _ p: String, group: Int = 1, url: Int? = nil) -> Pattern {
            Pattern(kind: kind, regex: try! NSRegularExpression(pattern: p), contentGroup: group, urlGroup: url)
        }
        // Priority order matters — earlier patterns CLAIM their range first, so later ones can't
        // re-match inside it: code is literal (a `*` inside `` `…` `` is never emphasis), then the IMAGE
        // pattern (BEFORE links — else the link regex grabs the `[alt](url)` and leaves a stray literal
        // `!`), then links, then autolinks, then the emphasis families LONGEST-DELIMITER-FIRST —
        // *** / ___ (bold+italic) before ** / __ (bold) before * / _ (italic) — else `***x***` is
        // grabbed as `**` + a stray `*`.
        //
        // ESCAPES: every delimiter opener carries a `(?<!\\)` guard, so a backslash-escaped delimiter
        // (`\*`, `\_`, `` \` ``, `\[`) does NOT open a span — the char is left as literal text. This is
        // a role suppression only: it never CLAIMS bytes, so a legitimate span that ENCLOSES an escaped
        // char (`**foo\_bar**`, `` `a\*b` ``) still matches and renders correctly (the earlier
        // claim-the-escape design broke exactly those). We deliberately don't dim the backslash — this
        // is a source-visible editor, so a literal `\*` reads honestly as `\*`.
        //
        // `_` is INTRAWORD-SAFE at every length: per CommonMark `_` can't open/close emphasis flanked by
        // word chars, so snake_case (`read_time_minutes`) never italicizes — the `(?<![\w\\])…(?!\w)`
        // guards enforce it. `*` keeps intraword emphasis (CommonMark allows `5*6*7`), un-guarded.
        // KNOWN LIMIT (intentional): the single-pass, no-delimiter-stack scan refuses `_a_b_` and renders
        // `**a*b*c**` as the inner italic only. Correctness here is "never wrongly italicize snake_case
        // / never clobber an enclosing span," not "match CommonMark for every adversarial run."
        return [
            make(.code, "(?<!\\\\)`([^`\\n]+)`"),
            // Wiki links claim right after code (still literal-code-safe: `[[x]]` in backticks is
            // already claimed) and BEFORE image/link — else the link regex could nibble a
            // `[[a]](b)`-shaped run, and `[[…]]` must never half-match as a `[…]` link.
            make(.wikiLink, "(?<!\\\\)\\[\\[([^\\[\\]\\n]+)\\]\\]"),
            make(.image, "(?<!\\\\)!\\[([^\\]\\n]*)\\]\\(([^)\\n]+)\\)", url: 2),   // alt may be empty: ![](p.png)
            make(.link, "(?<!\\\\)\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)", url: 2),     // url captured for click activation
            make(.link, "(?<!\\\\)<(https?://[^>\\s]+)>"),                            // angle autolink
            make(.link, "(?<![\\w@])https?://[^\\s<>()\\[\\]*]*[^\\s<>()\\[\\]*.,;:!?]", group: 0),  // bare URL — stops before *
            make(.strikethrough, "(?<!\\\\)~~([^~\\n]+)~~"),
            make(.highlight, "(?<!\\\\)==([^=\\n]+)=="),
            make(.strongEmphasis, "(?<!\\\\)\\*\\*\\*([^*\\n]+)\\*\\*\\*"),
            make(.strongEmphasis, "(?<![\\w\\\\])___([^_\\n]+)___(?!\\w)"),
            make(.strong, "(?<!\\\\)\\*\\*([^*\\n]+)\\*\\*"),
            make(.strong, "(?<![\\w\\\\])__([^_\\n]+)__(?!\\w)"),
            make(.emphasis, "(?<![*\\\\])\\*([^*\\n]+)\\*(?!\\*)"),
            make(.emphasis, "(?<![\\w\\\\])_([^_\\n]+)_(?!\\w)"),
        ]
    }()

    /// All inline spans in `text`, non-overlapping, sorted by position.
    public static func spans(in text: String) -> [InlineSpan] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var claimed = IndexSet()
        var result: [InlineSpan] = []

        for pattern in patterns {
            pattern.regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                let whole = match.range
                let span = whole.location..<(whole.location + whole.length)
                guard !claimed.intersects(integersIn: span) else { return }   // overlaps a claimed span
                let content = match.range(at: pattern.contentGroup)
                guard content.location != NSNotFound else { return }
                // Emphasis can't open on a blank run (CommonMark) — skip `_ _` / `* *` / `** **` so we
                // don't dim markers around a lone space.
                if pattern.kind == .strong || pattern.kind == .emphasis || pattern.kind == .strongEmphasis,
                   ns.substring(with: content).allSatisfy({ $0 == " " || $0 == "\t" }) {
                    return
                }
                let destination = pattern.urlGroup
                    .map { match.range(at: $0) }
                    .flatMap { $0.location == NSNotFound ? nil : $0 }
                claimed.insert(integersIn: span)
                result.append(InlineSpan(
                    kind: pattern.kind,
                    markerRanges: markerRanges(whole: whole, content: content),
                    contentRange: content,
                    destinationRange: destination
                ))
            }
        }
        return result.sorted { $0.contentRange.location < $1.contentRange.location }
    }

    /// The parts of `whole` outside `content` — the syntax scaffolding.
    private static func markerRanges(whole: NSRange, content: NSRange) -> [NSRange] {
        var ranges: [NSRange] = []
        if content.location > whole.location {
            ranges.append(NSRange(location: whole.location, length: content.location - whole.location))
        }
        let contentEnd = content.location + content.length
        let wholeEnd = whole.location + whole.length
        if wholeEnd > contentEnd {
            ranges.append(NSRange(location: contentEnd, length: wholeEnd - contentEnd))
        }
        return ranges
    }

    /// The single image span when `text`'s only non-whitespace content is one `![alt](url)` — the v1
    /// "block-level image" that renders as a picture. nil when the block wraps the image in other text
    /// (mid-paragraph inline images stay raw in v1) or isn't a lone image.
    public static func soleImageSpan(in text: String) -> InlineSpan? {
        let all = spans(in: text)
        guard all.count == 1, let span = all.first, span.kind == .image else { return nil }
        let ns = text as NSString
        let extent = span.markerRanges.reduce(span.contentRange) { NSUnionRange($0, $1) }
        guard extent.location >= 0, NSMaxRange(extent) <= ns.length else { return nil }
        let before = ns.substring(to: extent.location)
        let after = ns.substring(from: NSMaxRange(extent))
        guard before.allSatisfy(\.isWhitespace), after.allSatisfy(\.isWhitespace) else { return nil }
        return span
    }

    /// The raw destination (the `url` in a block-level `![alt](url)`), if `text` is a lone image.
    public static func soleImageURL(in text: String) -> String? {
        guard let span = soleImageSpan(in: text), let dest = span.destinationRange else { return nil }
        return (text as NSString).substring(with: dest)
    }
}
