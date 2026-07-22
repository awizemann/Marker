//
//  MarkdownContentText.swift
//  Marker
//
//  The "markers OFF" seam: a display-oriented projection of a block's verbatim source slice with
//  the block-level syntax markers stripped (leading `#`s, list markers, `>` prefixes, code fences).
//  Born from Scarf's renderer, which draws blocks as native views (SwiftUI Text/Grid) rather than
//  styling the raw source in place — such a consumer wants the CONTENT, not the markers.
//
//  This is deliberately a PROJECTION, not a mutation: `text`/`range` stay byte-exact (the core
//  invariant), and `contentText` is derived on demand. Inline markers (`**`, `` ` ``, links) are
//  NOT touched here — inline rendering is the consumer's business (`MarkdownInline.spans(in:)`
//  or the platform's own inline markdown support).
//

import Foundation

public nonisolated extension MarkdownBlock {

    /// The block's display text with block-level markers stripped and the trailing line
    /// terminator removed. What's stripped per kind:
    ///
    /// - `heading`: the leading `#`s and separating space, plus a trailing closing-hash run
    ///   (`## Title ##` → `Title`, per CommonMark's optional closing sequence).
    /// - `bulletItem` / `orderedItem`: the leading indent and `- ` / `1. ` / `1) ` marker.
    /// - `taskItem`: the marker AND the `[ ]` / `[x]` checkbox (the checked state already
    ///   lives in the block kind).
    /// - `blockquote`: the `>` prefix (and one following space) on every line; lines are
    ///   rejoined with `\n`.
    /// - `codeBlock`: the opening fence line and the closing fence line (when present) —
    ///   the interior is returned verbatim.
    /// - `paragraph` / `table`: nothing but the trailing terminator (a table's pipes are
    ///   structural — parse them with `MarkdownTable.parse`).
    /// - `blank` / `thematicBreak`: empty (the content IS the marker).
    var contentText: String {
        switch kind {
        case .blank, .thematicBreak:
            return ""
        case .paragraph, .table:
            return Self.trimmingTerminator(text)
        case .heading(let level):
            return Self.headingContent(Self.trimmingTerminator(text), level: level)
        case .bulletItem, .orderedItem:
            return Self.afterListMarker(Self.trimmingTerminator(text))
        case .taskItem:
            return Self.afterTaskMarker(Self.trimmingTerminator(text))
        case .blockquote:
            return Self.contentLines(text).map(Self.afterQuoteMarker).joined(separator: "\n")
        case .codeBlock:
            let lines = Self.contentLines(text)
            guard lines.count > 1 else { return "" }            // lone opening fence
            let closed = MarkdownParser.isFence(lines[lines.count - 1])
            return lines[1..<(lines.count - (closed ? 1 : 0))].joined(separator: "\n")
        }
    }

    // MARK: - Per-kind strippers

    private static func headingContent(_ line: String, level: Int) -> String {
        var t = line.drop { $0 == " " }
        t = t.dropFirst(level)
        if t.first == " " { t = t.dropFirst() }
        while t.last == " " { t = t.dropLast() }
        // Optional ATX closing sequence (`## Title ##`): a trailing run of `#` counts only when
        // preceded by a space or when it is the whole remainder — `# Title#` keeps its hash.
        var u = t
        var hashes = 0
        while u.last == "#" { u = u.dropLast(); hashes += 1 }
        if hashes > 0, u.isEmpty || u.last == " " {
            while u.last == " " { u = u.dropLast() }
            return String(u)
        }
        return String(t)
    }

    /// Strip `<indent><marker> ` where marker is `-`/`*`/`+` or `<digits>.`/`<digits>)`.
    private static func afterListMarker(_ line: String) -> String {
        var t = line.drop { $0 == " " }
        if let f = t.first, f == "-" || f == "*" || f == "+" {
            t = t.dropFirst()
        } else {
            t = t.drop { $0.isNumber }
            if t.first == "." || t.first == ")" { t = t.dropFirst() }
        }
        if t.first == " " { t = t.dropFirst() }
        return String(t)
    }

    /// Strip `<indent><marker> [x] ` — marker, checkbox, and one following space.
    private static func afterTaskMarker(_ line: String) -> String {
        var t = Substring(afterListMarker(line))                // "[x] content"
        if t.hasPrefix("["), t.dropFirst(2).first == "]" {
            t = t.dropFirst(3)
            if t.first == " " { t = t.dropFirst() }
        }
        return String(t)
    }

    private static func afterQuoteMarker(_ line: String) -> String {
        var t = line[...]
        var spaces = 0
        while t.first == " ", spaces < 3 { t = t.dropFirst(); spaces += 1 }
        if t.first == ">" {
            t = t.dropFirst()
            if t.first == " " { t = t.dropFirst() }
        }
        return String(t)
    }

    // MARK: - Line helpers (terminator-aware: \n, \r, \r\n)

    /// The block's lines with terminators removed (mirrors the parser's line scan).
    private static func contentLines(_ text: String) -> [String] {
        let ns = text as NSString
        var lines: [String] = []
        var index = 0
        while index < ns.length {
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
            lines.append(ns.substring(with: NSRange(location: index, length: contentsEnd - index)))
            index = lineEnd
        }
        return lines
    }

    /// Drop ONE trailing line terminator — the one the block's range owns. `\r\n` is a single
    /// Character (grapheme) in Swift, so a plain `dropLast()` handles all three forms.
    private static func trimmingTerminator(_ text: String) -> String {
        guard let last = text.last, last == "\n" || last == "\r" || last == "\r\n" else { return text }
        return String(text.dropLast())
    }
}
