//
//  MarkdownTable.swift
//  TrapperKeeperCore — Markdown
//
//  The PURE, byte-aware model behind grid-table rendering. `MarkdownParser` already groups
//  consecutive `|`-delimited lines into a `.table` block; this turns that block's verbatim source
//  slice into a structured grid (header / per-column alignment / data rows) WITHOUT touching bytes —
//  every cell carries its BLOCK-RELATIVE UTF-16 `NSRange` so a future click-to-edit can write back
//  through the ⌘K mutation seam (replace exactly that range) and keep the round-trip byte-exact.
//
//  Display-only fidelity, not a full GFM tokenizer: it handles the common shapes (optional outer
//  pipes, `:--:` alignment, backslash-escaped `\|`, ragged rows) and returns nil for anything that
//  isn't a real grid table (no separator row, no columns) so the caller falls back to plain styling.
//
//  nonisolated value types so the parse can run off the main actor alongside the block parse.
//

import Foundation

public nonisolated struct MarkdownTable: Sendable, Equatable {

    public enum Alignment: Sendable, Equatable {
        case left, center, right
    }

    /// One cell. `text` is the DISPLAY string (surrounding spaces trimmed, `\|` unescaped) — it does
    /// NOT necessarily equal the source substring. `range` is the BLOCK-RELATIVE UTF-16 range of the
    /// cell's trimmed source content (what a write-back would replace); it is a zero-length range at
    /// the row's end for a synthetic padding cell (a ragged row shorter than the header).
    public struct Cell: Sendable, Equatable {
        public let text: String
        public let range: NSRange
        public init(text: String, range: NSRange) {
            self.text = text
            self.range = range
        }
    }

    /// Header cells (defines the column count).
    public let header: [Cell]
    /// Per-column alignment, always `header.count` long (defaults to `.left`).
    public let alignments: [Alignment]
    /// Data rows, each normalized to exactly `header.count` cells (padded/truncated).
    public let rows: [[Cell]]

    public init(header: [Cell], alignments: [Alignment], rows: [[Cell]]) {
        self.header = header
        self.alignments = alignments
        self.rows = rows
    }

    public var columnCount: Int { header.count }

    /// Parse a `.table` block's verbatim source slice into a grid, or nil if it isn't a real grid
    /// table (needs a header line, a `|---|:--:|` separator as line 2, and ≥1 column). All ranges in
    /// the result are relative to `blockText` (add the block's `range.location` for document offsets).
    public static func parse(_ blockText: String) -> MarkdownTable? {
        let ns = blockText as NSString
        let lines = contentLines(ns)
        guard lines.count >= 2 else { return nil }

        // The first line is the header — it must not itself be a `|---|` separator (a block that
        // starts with a separator is a fragment, not a table).
        guard !isSeparatorLine(ns.substring(with: lines[0])) else { return nil }
        let header = splitRow(lines[0], in: ns)
        guard !header.isEmpty else { return nil }

        // The second line must be a separator with the SAME column count as the header (GFM); a
        // mismatch means it isn't a real grid table, so fall back to raw styling.
        guard isSeparatorLine(ns.substring(with: lines[1])) else { return nil }
        guard splitRow(lines[1], in: ns).count == header.count else { return nil }

        let alignments = parseAlignments(lines[1], in: ns, columns: header.count)
        var rows: [[Cell]] = []
        rows.reserveCapacity(max(0, lines.count - 2))
        for k in 2..<lines.count {
            rows.append(normalize(splitRow(lines[k], in: ns), to: header.count, rowEnd: NSMaxRange(lines[k])))
        }
        return MarkdownTable(header: header, alignments: alignments, rows: rows)
    }

    // MARK: - Lines (content ranges, terminator-excluded, blank lines dropped)

    /// Split the block into per-line CONTENT ranges (excluding the line terminator). Trailing blank
    /// lines — a table block ends with a terminator, so the final "line" past it is empty — are
    /// dropped so they don't masquerade as an empty data row.
    private static func contentLines(_ ns: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var index = 0
        let length = ns.length
        while index < length {
            var lineEnd = 0, contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
            let content = NSRange(location: index, length: contentsEnd - index)
            if !isBlank(ns.substring(with: content)) { result.append(content) }
            index = lineEnd
        }
        return result
    }

    private static func isBlank(_ s: String) -> Bool { s.allSatisfy { $0 == " " || $0 == "\t" } }

    // MARK: - Row splitting (unescaped `|` only; optional outer pipes)

    /// Split one row's content range into cells on UNESCAPED pipes, dropping the optional single outer
    /// pipe on each side. Returns cells with block-relative trimmed-content ranges + unescaped display
    /// text. An empty interior (`||` or a bare `|`) yields no cells (caller treats as not-a-table for
    /// the header).
    private static func splitRow(_ content: NSRange, in ns: NSString) -> [Cell] {
        // Trim surrounding whitespace of the whole row (up to the content bounds).
        var start = content.location
        var end = NSMaxRange(content)
        while start < end, isSpace(ns.character(at: start)) { start += 1 }
        while end > start, isSpace(ns.character(at: end - 1)) { end -= 1 }
        guard start < end else { return [] }

        // Optional single leading pipe.
        if ns.character(at: start) == pipe { start += 1 }
        // Optional single trailing pipe — only if it's not backslash-escaped.
        if end > start, ns.character(at: end - 1) == pipe, !isEscaped(at: end - 1, from: content.location, in: ns) {
            end -= 1
        }
        guard start <= end else { return [] }

        var cells: [Cell] = []
        var cellStart = start
        var i = start
        while i < end {
            if ns.character(at: i) == pipe, !isEscaped(at: i, from: content.location, in: ns) {
                cells.append(makeCell(from: cellStart, to: i, in: ns))
                cellStart = i + 1
            }
            i += 1
        }
        cells.append(makeCell(from: cellStart, to: end, in: ns))
        // A row that is only the outer pipe(s) — `|`, `||`, `| |` — has one empty cell and no interior
        // delimiter; yield no cells so `parse` rejects it (a bare-pipe line is not a real table row).
        if cells.count == 1, cells[0].range.length == 0 { return [] }
        return cells
    }

    /// Trim surrounding spaces from `[lo, hi)`, then build a cell with the trimmed source range and
    /// the `\|`-unescaped display text.
    private static func makeCell(from lo: Int, to hi: Int, in ns: NSString) -> Cell {
        var s = lo, e = hi
        while s < e, isSpace(ns.character(at: s)) { s += 1 }
        while e > s, isSpace(ns.character(at: e - 1)) { e -= 1 }
        let range = NSRange(location: s, length: e - s)
        return Cell(text: unescapePipes(ns.substring(with: range)), range: range)
    }

    /// A pipe at `index` is escaped iff preceded by an ODD run of backslashes (so `\|` is escaped but
    /// `\\|` is a literal backslash then a real delimiter). `lowerBound` caps the backward scan to the
    /// row's own content.
    private static func isEscaped(at index: Int, from lowerBound: Int, in ns: NSString) -> Bool {
        var backslashes = 0
        var j = index - 1
        while j >= lowerBound, ns.character(at: j) == backslash { backslashes += 1; j -= 1 }
        return backslashes % 2 == 1
    }

    private static func unescapePipes(_ s: String) -> String {
        s.contains("\\|") ? s.replacingOccurrences(of: "\\|", with: "|") : s
    }

    // MARK: - Separator / alignment row

    /// A `|---|:--:|` separator: after stripping optional outer pipes, EVERY cell is `:?-+:?` (at
    /// least one dash), and the line contains only pipes, dashes, colons, and spaces.
    static func isSeparatorLine(_ content: String) -> Bool {
        let t = content.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        guard t.allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }) else { return false }
        let inner = t.hasPrefix("|") ? String(t.dropFirst()) : t
        let inner2 = inner.hasSuffix("|") ? String(inner.dropLast()) : inner
        let cells = inner2.split(separator: "|", omittingEmptySubsequences: false)
        guard !cells.isEmpty else { return false }
        for cell in cells {
            let c = cell.trimmingCharacters(in: .whitespaces)
            guard !c.isEmpty, c.contains("-") else { return false }
            // Strip one optional colon at each end; the core must be dashes only (colons only at ends).
            let body = c.hasPrefix(":") ? c.dropFirst() : c[...]
            let core = body.hasSuffix(":") ? body.dropLast() : body
            guard !core.isEmpty, core.allSatisfy({ $0 == "-" }) else { return false }
        }
        return true
    }

    /// Map the separator row's cells to per-column alignment, padded/truncated to `columns` (default
    /// `.left`). `:x:` → center, `x:` → right, `:x`/`x` → left.
    private static func parseAlignments(_ content: NSRange, in ns: NSString, columns: Int) -> [Alignment] {
        let cells = splitRow(content, in: ns)
        var result: [Alignment] = cells.map { cell in
            // Read the RAW trimmed source (not the unescaped display) — separators have no escapes.
            let raw = ns.substring(with: cell.range)
            let leading = raw.hasPrefix(":")
            let trailing = raw.hasSuffix(":")
            switch (leading, trailing) {
            case (true, true):   return .center
            case (false, true):  return .right
            default:             return .left
            }
        }
        if result.count < columns { result.append(contentsOf: Array(repeating: .left, count: columns - result.count)) }
        if result.count > columns { result = Array(result.prefix(columns)) }
        return result
    }

    // MARK: - Row normalization

    /// Pad a short row with empty cells (zero-length range at the row's end) or truncate a long one so
    /// every data row has exactly `count` cells matching the header.
    private static func normalize(_ cells: [Cell], to count: Int, rowEnd: Int) -> [Cell] {
        if cells.count == count { return cells }
        if cells.count > count { return Array(cells.prefix(count)) }
        var padded = cells
        padded.append(contentsOf: (cells.count..<count).map { _ in Cell(text: "", range: NSRange(location: rowEnd, length: 0)) })
        return padded
    }

    // MARK: - Char helpers (UTF-16 units)

    private static let pipe = UInt16(UInt8(ascii: "|"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static func isSpace(_ u: UInt16) -> Bool { u == 0x20 || u == 0x09 }
}
