//
//  MarkdownParser.swift
//  Marker — (ex TrapperKeeperCore) Markdown (P1.1)
//
//  A line-oriented scanner that classifies the source into TILING blocks (see memory: "Editor
//  architecture: raw-string storage + attribute styling"). It NEVER transforms the source — it only
//  records ranges into it — so the block model is a lossless view of the file's bytes.
//
//  Spike-level coverage: headings, paragraphs, blockquotes, bullet/ordered/task list items, fenced
//  code, tables, thematic breaks, and blanks. Continuations/nesting/setext headings degrade to
//  paragraph; that's fine — the worst case is a block rendered as plain text, never lost bytes.
//

import Foundation

public enum MarkdownParser {

    public static func parse(_ source: String) -> MarkdownDocument {
        let ns = source as NSString
        let lines = scanLines(ns)
        var blocks: [MarkdownBlock] = []
        var nextID = 0
        var i = 0

        func emit(_ kind: BlockKind, from start: Int, to end: Int, indent: Int = 0) {
            let range = NSRange(location: start, length: end - start)
            blocks.append(MarkdownBlock(id: nextID, kind: kind, range: range, text: ns.substring(with: range), indent: indent))
            nextID += 1
        }

        while i < lines.count {
            let line = lines[i]
            let content = line.content

            // Fenced code block: consume through the closing fence (or to EOF if unterminated). The
            // interior is NOT classified, so a `# foo` inside a fence stays code, not a heading.
            // (A fence opener with no language is still a fence — detect with isFence, not the
            // optional language, which is nil for both "no language" and "not a fence".)
            if isFence(content) {
                let language = fenceLanguage(content)
                let start = line.range.location
                var end = NSMaxRange(line.range)
                var j = i + 1
                while j < lines.count {
                    end = NSMaxRange(lines[j].range)
                    let closed = isFence(lines[j].content)
                    j += 1
                    if closed { break }
                }
                emit(.codeBlock(language: language), from: start, to: end)
                i = j
                continue
            }

            // Single-line blocks.
            if isBlank(content) { emit(.blank, from: line.range.location, to: NSMaxRange(line.range)); i += 1; continue }
            if isThematicBreak(content) { emit(.thematicBreak, from: line.range.location, to: NSMaxRange(line.range)); i += 1; continue }
            if let level = headingLevel(content) { emit(.heading(level: level), from: line.range.location, to: NSMaxRange(line.range)); i += 1; continue }
            if let checked = taskState(content) { emit(.taskItem(checked: checked), from: line.range.location, to: NSMaxRange(line.range), indent: leadingSpaces(content)); i += 1; continue }
            if let marker = bulletMarker(content) { emit(.bulletItem(marker: marker), from: line.range.location, to: NSMaxRange(line.range), indent: leadingSpaces(content)); i += 1; continue }
            if let number = orderedNumber(content) { emit(.orderedItem(number: number), from: line.range.location, to: NSMaxRange(line.range), indent: leadingSpaces(content)); i += 1; continue }

            // Multi-line greedy blocks.
            if isBlockquote(content) { i = consume(.blockquote, from: i, lines: lines, while: isBlockquote, emit: emit); continue }
            if isTableRow(content) { i = consume(.table, from: i, lines: lines, while: isTableRow, emit: emit); continue }

            // Paragraph: greedily absorb following "plain" lines (anything not a block starter).
            i = consume(.paragraph, from: i, lines: lines, while: isParagraphContinuation, emit: emit)
        }

        return MarkdownDocument(source: source, blocks: blocks)
    }

    // MARK: - Line scanning (terminator-preserving)

    private struct Line { let range: NSRange; let content: String }   // range incl. terminator; content excl.

    /// Split into lines using Foundation's line enumeration, which treats \n, \r, and \r\n as single
    /// terminators. `range` includes the terminator (so ranges tile); `content` excludes it.
    private static func scanLines(_ ns: NSString) -> [Line] {
        var lines: [Line] = []
        var index = 0
        let length = ns.length
        while index < length {
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
            lines.append(Line(
                range: NSRange(location: index, length: lineEnd - index),
                content: ns.substring(with: NSRange(location: index, length: contentsEnd - index))
            ))
            index = lineEnd
        }
        return lines
    }

    /// Emit one block spanning lines `start...` while `predicate` holds, returning the next index.
    private static func consume(
        _ kind: BlockKind, from start: Int, lines: [Line],
        while predicate: (String) -> Bool,
        emit: (BlockKind, Int, Int, Int) -> Void
    ) -> Int {
        let startLoc = lines[start].range.location
        var end = NSMaxRange(lines[start].range)
        var j = start + 1
        while j < lines.count, predicate(lines[j].content) {
            end = NSMaxRange(lines[j].range)
            j += 1
        }
        emit(kind, startLoc, end, 0)   // greedy blocks (quote/table/paragraph) are never list items
        return j
    }

    // MARK: - Line classifiers (operate on terminator-stripped content)

    private static func leadingTrimmed(_ s: String) -> Substring {
        // Up to 3 leading spaces are allowed before most block markers (CommonMark); keep it simple.
        var sub = s[...]
        var spaces = 0
        while let f = sub.first, f == " ", spaces < 3 { sub = sub.dropFirst(); spaces += 1 }
        return sub
    }

    /// Strip ALL leading spaces (unlike `leadingTrimmed`, which caps at 3). The LIST classifiers use
    /// this so a nested item indented past 3 spaces is still recognized as a list item (we don't do
    /// indented-code blocks, so relaxing the cap for lists is safe); `leadingSpaces` records the depth.
    private static func fullyTrimmed(_ s: String) -> Substring {
        var sub = s[...]
        while sub.first == " " { sub = sub.dropFirst() }
        return sub
    }

    /// Count of leading spaces on a line — the nested-list indent signal recorded on the block.
    static func leadingSpaces(_ s: String) -> Int {
        var n = 0
        for c in s { if c == " " { n += 1 } else { break } }
        return n
    }

    static func isBlank(_ s: String) -> Bool { s.allSatisfy { $0 == " " || $0 == "\t" } }

    static func headingLevel(_ s: String) -> Int? {
        let t = leadingTrimmed(s)
        var hashes = 0
        var it = t.startIndex
        while it < t.endIndex, t[it] == "#", hashes < 7 { hashes += 1; it = t.index(after: it) }
        guard (1...6).contains(hashes) else { return nil }
        // Must be followed by a space or end-of-line (ATX heading), else it's not a heading.
        guard it == t.endIndex || t[it] == " " else { return nil }
        return hashes
    }

    static func isThematicBreak(_ s: String) -> Bool {
        let t = leadingTrimmed(s).filter { $0 != " " }
        guard t.count >= 3 else { return false }
        return t.allSatisfy { $0 == "-" } || t.allSatisfy { $0 == "*" } || t.allSatisfy { $0 == "_" }
    }

    /// `- [ ] ` / `- [x] ` / `* [X] ` → task item (checked?).
    static func taskState(_ s: String) -> Bool? {
        let t = fullyTrimmed(s)
        guard let first = t.first, first == "-" || first == "*" || first == "+" else { return nil }
        let rest = t.dropFirst()
        guard rest.first == " " else { return nil }
        let afterMarker = rest.dropFirst()
        guard afterMarker.hasPrefix("[") else { return nil }
        let box = afterMarker.dropFirst()                       // after '['
        guard let mark = box.first, box.dropFirst().first == "]" else { return nil }
        switch mark {
        case " ": return false
        case "x", "X": return true
        default: return nil
        }
    }

    static func bulletMarker(_ s: String) -> Character? {
        let t = fullyTrimmed(s)
        guard let first = t.first, first == "-" || first == "*" || first == "+" else { return nil }
        guard t.dropFirst().first == " " else { return nil }    // needs a space after the marker
        return first
    }

    static func orderedNumber(_ s: String) -> Int? {
        let t = fullyTrimmed(s)
        var digits = ""
        var it = t.startIndex
        while it < t.endIndex, t[it].isNumber, digits.count < 9 { digits.append(t[it]); it = t.index(after: it) }
        guard !digits.isEmpty, it < t.endIndex, t[it] == "." || t[it] == ")" else { return nil }
        let after = t.index(after: it)
        guard after == t.endIndex || t[after] == " " else { return nil }
        return Int(digits)
    }

    static func isBlockquote(_ s: String) -> Bool { leadingTrimmed(s).first == ">" }

    static func isTableRow(_ s: String) -> Bool {
        let t = leadingTrimmed(s)
        return t.first == "|" && t.contains("|") && !t.isEmpty
    }

    /// A fenced-code opener/closer line: ``` or ~~~ (3+), optional language after an opener.
    static func fenceLanguage(_ s: String) -> String? {
        let t = leadingTrimmed(s)
        guard t.hasPrefix("```") || t.hasPrefix("~~~") else { return nil }
        let fenceChar = t.first!
        let afterFence = t.drop { $0 == fenceChar }
        let lang = afterFence.trimmingCharacters(in: .whitespaces)
        return lang.isEmpty ? nil : lang   // nil language is still a valid fence (handled by isFence)
    }

    static func isFence(_ s: String) -> Bool {
        let t = leadingTrimmed(s)
        return t.hasPrefix("```") || t.hasPrefix("~~~")
    }

    /// A line continues a paragraph when it isn't blank and starts no other block.
    static func isParagraphContinuation(_ s: String) -> Bool {
        if isBlank(s) { return false }
        if isFence(s) || isThematicBreak(s) || isBlockquote(s) || isTableRow(s) { return false }
        if headingLevel(s) != nil || taskState(s) != nil || bulletMarker(s) != nil || orderedNumber(s) != nil { return false }
        return true
    }
}
