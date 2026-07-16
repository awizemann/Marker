//
//  EditorCommands.swift
//  TrapperKeeperCore — Editor (P4.1)
//
//  The PURE, byte-precise logic the ⌘K palette runs against — no UI, no NSTextView. Each command maps
//  (current raw text + selection) → a single `TextEdit`: an exact UTF-16 range to replace, the
//  replacement string, and the selection to leave behind. The host applies it through the text view so
//  undo registers and the model reparses (see EditorModel.runCommand / EditorTextMutating).
//
//  Everything works in NSString / UTF-16 to match the NSTextView coordinate space. The editor's
//  internal line terminator is LF (CRLF is normalized on load, re-encoded on save), so the line logic
//  here assumes `\n`. Edits are precise range replacements — never a lossy whole-text rewrite.
//

import Foundation

/// One precise edit: replace `range` (in the ORIGINAL text) with `replacement`, then place the
/// caret/selection at `selectionAfter` (in the NEW text's coordinates).
public nonisolated struct TextEdit: Sendable, Equatable {
    public let range: NSRange
    public let replacement: String
    public let selectionAfter: NSRange

    public init(range: NSRange, replacement: String, selectionAfter: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selectionAfter = selectionAfter
    }
}

/// The ⌘K palette's tools. Nearly all are document mutations (inline wraps toggle; headings/
/// line-prefixes toggle; inserts drop a starter block; line ops transform the selected lines).
/// `copyCodeBlock` is the ONE non-mutating action — a side effect (copy to the clipboard), so it
/// produces no `TextEdit` and the host routes it through the `SystemActions` seam instead.
/// (Math/mermaid/footnote + jump-to-heading are deliberately out of scope — P5 / navigation.)
public nonisolated enum EditorCommand: Sendable, Equatable {
    case bold, italic, inlineCode, strikethrough, highlight        // inline wrap/toggle
    case heading(Int)                                              // 1...3 — toggle the line's level
    case bulletList, orderedList, taskList, blockquote             // toggle a line prefix across selection
    case codeBlock, table, link, frontmatter                      // insert a starter block
    case sortLines, dedupeLines, titleCaseLines                   // operate on the selected lines
    case copyCodeBlock                                            // side-effect: copy the caret's code block (no edit)
    case addImage, addWebImage                                   // side-effect: insert an image (local file / web url)

    /// The inline delimiter for the wrap commands (nil for non-wrap commands).
    var wrapMarker: String? {
        switch self {
        case .bold: return "**"
        case .italic: return "*"
        case .inlineCode: return "`"
        case .strikethrough: return "~~"
        case .highlight: return "=="
        default: return nil
        }
    }
}

public nonisolated enum EditorCommands {

    /// Compute the edit for `command` given the current `text` and `selection`. Returns `nil` when the
    /// command doesn't apply (e.g. a line op with no real selection), so the caller can no-op cleanly.
    public static func textEdit(for command: EditorCommand, in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        guard selection.location >= 0, NSMaxRange(selection) <= ns.length else { return nil }

        if let marker = command.wrapMarker {
            return wrap(marker, in: ns, selection: selection)
        }
        switch command {
        case .heading(let level):       return heading(level, in: ns, selection: selection)
        case .bulletList:               return linePrefix(.bullet, in: ns, selection: selection)
        case .orderedList:              return linePrefix(.ordered, in: ns, selection: selection)
        case .taskList:                 return linePrefix(.task, in: ns, selection: selection)
        case .blockquote:               return linePrefix(.quote, in: ns, selection: selection)
        case .codeBlock:                return insertCodeBlock(in: ns, selection: selection)
        case .table:                    return insertTable(in: ns, selection: selection)
        case .link:                     return insertLink(in: ns, selection: selection)
        case .frontmatter:              return insertFrontmatter(in: ns)
        case .sortLines:                return lineOp(.sort, in: ns, selection: selection)
        case .dedupeLines:              return lineOp(.dedupe, in: ns, selection: selection)
        case .titleCaseLines:           return lineOp(.titleCase, in: ns, selection: selection)
        default:                        return nil   // wrap commands handled above
        }
    }

    // MARK: - Newline continuation (Enter in a list/quote)

    /// The edit for pressing Enter on a list/quote line: continue the marker on a new line, or — on an
    /// EMPTY item (just the marker) — remove the marker to exit the list. Returns `nil` for a normal
    /// line (caret only; the host falls back to a plain newline). Ordered lists renumber by +1.
    public static func newlineContinuation(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0, selection.location >= 0 else { return nil }
        let ns = text as NSString
        guard selection.location <= ns.length else { return nil }
        let lineRange = contentLineRange(at: selection.location, in: ns)
        let line = ns.substring(with: lineRange)
        guard let cont = listContinuation(line) else { return nil }

        if cont.contentEmpty {
            // Empty item + Enter → exit the list: strip the marker (no newline added).
            return TextEdit(range: NSRange(location: lineRange.location, length: cont.markerLength),
                            replacement: "",
                            selectionAfter: NSRange(location: lineRange.location, length: 0))
        }
        // Continue: insert a newline + the next marker at the caret.
        let insert = "\n" + cont.nextMarker
        return TextEdit(range: NSRange(location: selection.location, length: 0),
                        replacement: insert,
                        selectionAfter: NSRange(location: selection.location + (insert as NSString).length, length: 0))
    }

    private static let taskContinuationRE  = try! NSRegularExpression(pattern: "^(\\s*)([-*+]) \\[[ xX]\\] ")
    private static let bulletContinuationRE = try! NSRegularExpression(pattern: "^(\\s*)([-*+]) ")
    private static let orderedContinuationRE = try! NSRegularExpression(pattern: "^(\\s*)(\\d+)\\. ")
    private static let quoteContinuationRE  = try! NSRegularExpression(pattern: "^(\\s*)> ")

    /// If `line` starts with a list/quote marker, return its UTF-16 length, the marker to start the
    /// NEXT line with (indent preserved; ordered incremented), and whether the item has no content.
    private static func listContinuation(_ line: String) -> (markerLength: Int, nextMarker: String, contentEmpty: Bool)? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)

        func contentEmpty(after markerLen: Int) -> Bool {
            ns.substring(from: markerLen).trimmingCharacters(in: .whitespaces).isEmpty
        }
        if let m = taskContinuationRE.firstMatch(in: line, range: full) {
            let len = m.range.length
            let indent = ns.substring(with: m.range(at: 1)), bullet = ns.substring(with: m.range(at: 2))
            return (len, "\(indent)\(bullet) [ ] ", contentEmpty(after: len))
        }
        if let m = bulletContinuationRE.firstMatch(in: line, range: full) {
            let len = m.range.length
            let indent = ns.substring(with: m.range(at: 1)), bullet = ns.substring(with: m.range(at: 2))
            return (len, "\(indent)\(bullet) ", contentEmpty(after: len))
        }
        if let m = orderedContinuationRE.firstMatch(in: line, range: full) {
            let len = m.range.length
            let indent = ns.substring(with: m.range(at: 1))
            let n = Int(ns.substring(with: m.range(at: 2))) ?? 0
            return (len, "\(indent)\(n + 1). ", contentEmpty(after: len))
        }
        if let m = quoteContinuationRE.firstMatch(in: line, range: full) {
            let len = m.range.length
            let indent = ns.substring(with: m.range(at: 1))
            return (len, "\(indent)> ", contentEmpty(after: len))
        }
        return nil
    }

    // MARK: - Inline wrap / toggle

    private static func wrap(_ marker: String, in ns: NSString, selection: NSRange) -> TextEdit {
        let mLen = (marker as NSString).length

        // Empty caret → insert the pair with the caret between the markers.
        guard selection.length > 0 else {
            return TextEdit(range: selection, replacement: marker + marker,
                            selectionAfter: NSRange(location: selection.location + mLen, length: 0))
        }

        let selected = ns.substring(with: selection)

        // Toggle-off A: the selection itself is the wrapped span (`**bold**` selected) → strip the markers.
        if selection.length >= 2 * mLen, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(with: NSRange(location: mLen, length: selection.length - 2 * mLen))
            return TextEdit(range: selection, replacement: inner,
                            selectionAfter: NSRange(location: selection.location, length: (inner as NSString).length))
        }

        // Toggle-off B: the markers sit immediately OUTSIDE the selection (`**[bold]**`) → strip them.
        let beforeLoc = selection.location - mLen
        let afterLoc = NSMaxRange(selection)
        if beforeLoc >= 0, afterLoc + mLen <= ns.length,
           variantBToggleOff(ns, marker: marker, mLen: mLen, beforeLoc: beforeLoc, afterLoc: afterLoc) {
            return TextEdit(range: NSRange(location: beforeLoc, length: selection.length + 2 * mLen),
                            replacement: selected,
                            selectionAfter: NSRange(location: beforeLoc, length: selection.length))
        }

        // Otherwise wrap the non-whitespace CORE of the selection, so the markers hug the text — a
        // trailing newline (or surrounding spaces) in the selection must NOT push the closing marker
        // onto the next line (the "italic broke it" bug). The inner content stays selected (re-applying
        // toggles off).
        let core = trimmedCore(selection, in: ns)
        guard core.length > 0 else {
            return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: marker + marker,
                            selectionAfter: NSRange(location: selection.location + mLen, length: 0))
        }
        let coreText = ns.substring(with: core)
        return TextEdit(range: core, replacement: marker + coreText + marker,
                        selectionAfter: NSRange(location: core.location + mLen, length: core.length))
    }

    /// The selection narrowed to its non-whitespace core (leading/trailing spaces, tabs, and newlines
    /// excluded), so a wrap keeps its markers adjacent to the text.
    private static func trimmedCore(_ range: NSRange, in ns: NSString) -> NSRange {
        func isWS(_ u: unichar) -> Bool { u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0D }
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isWS(ns.character(at: start)) { start += 1 }
        while end > start, isWS(ns.character(at: end - 1)) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Whether the markers just outside the selection are a genuine wrap to strip. For a SINGLE-char
    /// marker (`*`, `` ` ``), require the char beyond it isn't the same — so italicizing the inner of
    /// `**bold**` doesn't strip one `*` from each `**` (which would drop the bold). Then it falls through
    /// to WRAP, giving `***bold***` (bold + italic) as the user intends.
    private static func variantBToggleOff(_ ns: NSString, marker: String, mLen: Int, beforeLoc: Int, afterLoc: Int) -> Bool {
        guard ns.substring(with: NSRange(location: beforeLoc, length: mLen)) == marker,
              ns.substring(with: NSRange(location: afterLoc, length: mLen)) == marker else { return false }
        guard mLen == 1, let ch = marker.utf16.first else { return true }   // multi-char markers: no extra guard
        let leftClear = beforeLoc == 0 || ns.character(at: beforeLoc - 1) != ch
        let rightClear = afterLoc + mLen >= ns.length || ns.character(at: afterLoc + mLen) != ch
        return leftClear && rightClear
    }

    // MARK: - Headings (single line, toggle level)

    private static func heading(_ level: Int, in ns: NSString, selection: NSRange) -> TextEdit? {
        guard (1...6).contains(level) else { return nil }
        // Headings are single-line — operate on the line holding the selection's start.
        let lineRange = contentLineRange(at: selection.location, in: ns)
        let line = ns.substring(with: lineRange)
        let bare = strippedHeadingPrefix(line)
        let prefix = String(repeating: "#", count: level) + " "

        let replacement: String
        if currentHeadingLevel(line) == level {
            replacement = bare                                  // same level → toggle off to paragraph
        } else {
            replacement = prefix + bare                         // set (or change) the level
        }
        // Preserve the caret's column: shift it by the change in prefix length, clamped to the new line.
        let oldPrefixLen = (line as NSString).length - (bare as NSString).length
        let newPrefixLen = (replacement as NSString).length - (bare as NSString).length
        let lineEnd = lineRange.location + (replacement as NSString).length
        let caret = min(max(selection.location + (newPrefixLen - oldPrefixLen), lineRange.location), lineEnd)
        return TextEdit(range: lineRange, replacement: replacement,
                        selectionAfter: NSRange(location: caret, length: 0))
    }

    // MARK: - Line-prefix block toggles (across all selected lines)

    private enum LinePrefix { case bullet, ordered, task, quote }

    private static func linePrefix(_ kind: LinePrefix, in ns: NSString, selection: NSRange) -> TextEdit {
        let span = ns.lineRange(for: selection)
        let (lines, trailingNewline) = splitLines(ns.substring(with: span))
        let isBlank: (String) -> Bool = { $0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Toggle off only when EVERY non-blank line already carries THIS EXACT kind's prefix.
        let nonBlank = lines.filter { !isBlank($0) }
        let allPrefixed = !nonBlank.isEmpty && nonBlank.allSatisfy { hasPrefix(kind, $0) }
        // Skip blank lines only when there's real content to prefix (don't bullet the gaps in a
        // multi-line selection). On an all-blank selection (empty doc / a caret on an empty line),
        // apply anyway so ⌘K → list STARTS a list item.
        let hasContent = !nonBlank.isEmpty

        var ordinal = 1
        let transformed: [String] = lines.map { line in
            if hasContent && isBlank(line) { return line }   // leave intra-selection blank lines be
            if allPrefixed { return removePrefix(kind, line) }
            let n = ordinal; ordinal += 1
            switch kind {
            case .bullet, .ordered, .task:
                // CONVERT: strip any existing list marker (so a mixed-kind selection unifies, and we
                // never double-prefix), then add this kind's marker.
                return addPrefix(kind, stripAnyListMarker(line), ordinal: n)
            case .quote:
                // Quote WRAPS (it can quote a list line) — add only if absent, never strip.
                return hasPrefix(.quote, line) ? line : addPrefix(.quote, line, ordinal: n)
            }
        }
        let rebuilt = transformed.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let selLen = max(0, (rebuilt as NSString).length - (trailingNewline ? 1 : 0))
        return TextEdit(range: span, replacement: rebuilt,
                        selectionAfter: NSRange(location: span.location, length: selLen))
    }

    /// EXACT per-kind prefix detection. `.bullet` deliberately EXCLUDES the task form (`- [ ] `) via a
    /// negative lookahead, so a task line isn't mistaken for an already-bulleted line.
    private static func hasPrefix(_ kind: LinePrefix, _ line: String) -> Bool {
        switch kind {
        case .bullet: return line.range(of: "^\\s*[-*+] (?!\\[[ xX]\\] )", options: .regularExpression) != nil
        case .ordered: return line.range(of: "^\\s*\\d+\\. ", options: .regularExpression) != nil
        case .task:   return line.range(of: "^\\s*[-*+] \\[[ xX]\\] ", options: .regularExpression) != nil
        case .quote:  return line.range(of: "^\\s*> ", options: .regularExpression) != nil
        }
    }

    /// Strip ANY leading list/task marker (task form first, since it's the longest), preserving indent.
    private static func stripAnyListMarker(_ line: String) -> String {
        line.replacingOccurrences(of: "^(\\s*)(?:[-*+] \\[[ xX]\\] |[-*+] |\\d+\\. )", with: "$1",
                                  options: .regularExpression)
    }

    private static func addPrefix(_ kind: LinePrefix, _ line: String, ordinal: Int) -> String {
        switch kind {
        case .bullet: return "- " + line
        case .ordered: return "\(ordinal). " + line
        case .task:   return "- [ ] " + line
        case .quote:  return "> " + line
        }
    }

    private static func removePrefix(_ kind: LinePrefix, _ line: String) -> String {
        let pattern: String
        switch kind {
        case .bullet: pattern = "^(\\s*)[-*+] "
        case .ordered: pattern = "^(\\s*)\\d+\\. "
        case .task:   pattern = "^(\\s*)[-*+] \\[[ xX]\\] "
        case .quote:  pattern = "^(\\s*)> "
        }
        return line.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
    }

    // MARK: - Inserts

    private static func insertCodeBlock(in ns: NSString, selection: NSRange) -> TextEdit {
        if selection.length > 0 {
            let body = ns.substring(with: selection)
            let replacement = "```\n" + body + "\n```"
            return TextEdit(range: selection, replacement: replacement,
                            selectionAfter: NSRange(location: selection.location + 4, length: (body as NSString).length))
        }
        let replacement = "```\n\n```"
        return TextEdit(range: selection, replacement: replacement,
                        selectionAfter: NSRange(location: selection.location + 4, length: 0))   // caret on the empty middle line
    }

    private static func insertTable(in ns: NSString, selection: NSRange) -> TextEdit {
        let table = "| Column | Column |\n| --- | --- |\n| Cell | Cell |\n"
        // Anchor AFTER any selection (length 0 — we never delete the user's selected text) and put the
        // table on its own line.
        let anchor = NSMaxRange(selection)
        let atLineStart = anchor == 0 || ns.character(at: anchor - 1) == 0x0A
        let lead = atLineStart ? "" : "\n"
        let replacement = lead + table
        // Select the first "Column" header so the user can type over it.
        let firstCell = anchor + (lead as NSString).length + 2   // past the lead newline + "| "
        return TextEdit(range: NSRange(location: anchor, length: 0),
                        replacement: replacement,
                        selectionAfter: NSRange(location: firstCell, length: 6))
    }

    private static func insertLink(in ns: NSString, selection: NSRange) -> TextEdit {
        if selection.length > 0 {
            let label = ns.substring(with: selection)
            let replacement = "[" + label + "](url)"
            // Select the "url" placeholder.
            let urlLoc = selection.location + 1 + (label as NSString).length + 2   // [ + label + ](
            return TextEdit(range: selection, replacement: replacement,
                            selectionAfter: NSRange(location: urlLoc, length: 3))
        }
        let replacement = "[text](url)"
        return TextEdit(range: selection, replacement: replacement,
                        selectionAfter: NSRange(location: selection.location + 1, length: 4))   // select "text"
    }

    private static func insertFrontmatter(in ns: NSString) -> TextEdit? {
        // Only when there isn't ALREADY a frontmatter block. A doc that merely opens with a thematic
        // break (`---\n\nText`) is NOT frontmatter — it needs a real CLOSING `---` fence to count.
        if hasFrontmatter(ns) { return nil }
        let replacement = "---\n\n---\n"
        return TextEdit(range: NSRange(location: 0, length: 0), replacement: replacement,
                        selectionAfter: NSRange(location: 4, length: 0))   // caret on the empty middle line
    }

    /// True iff the first line is exactly `---` AND a later line is exactly `---` (the closing fence).
    private static func hasFrontmatter(_ ns: NSString) -> Bool {
        let first = ns.lineRange(for: NSRange(location: 0, length: 0))
        guard ns.substring(with: first).trimmingCharacters(in: .newlines) == "---" else { return false }
        var start = NSMaxRange(first)
        while start < ns.length {
            let lr = ns.lineRange(for: NSRange(location: start, length: 0))
            if ns.substring(with: lr).trimmingCharacters(in: .newlines) == "---" { return true }
            start = NSMaxRange(lr)
            if lr.length == 0 { break }
        }
        return false
    }

    // MARK: - Operate on the selected lines

    private enum LineOp { case sort, dedupe, titleCase }

    private static func lineOp(_ op: LineOp, in ns: NSString, selection: NSRange) -> TextEdit? {
        guard selection.length > 0 else { return nil }   // line ops need a selection to act on
        let span = ns.lineRange(for: selection)
        let (lines, trailingNewline) = splitLines(ns.substring(with: span))
        guard lines.count > 0 else { return nil }

        let transformed: [String]
        switch op {
        case .sort:
            transformed = lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        case .dedupe:
            var seen = Set<String>()
            transformed = lines.filter { seen.insert($0).inserted }
        case .titleCase:
            transformed = lines.map(titleCased)
        }
        let rebuilt = transformed.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let selLen = max(0, (rebuilt as NSString).length - (trailingNewline ? 1 : 0))
        return TextEdit(range: span, replacement: rebuilt,
                        selectionAfter: NSRange(location: span.location, length: selLen))
    }

    // MARK: - Helpers

    /// The range of the single line containing `location`, EXCLUDING its trailing line terminator.
    private static func contentLineRange(at location: Int, in ns: NSString) -> NSRange {
        let full = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        var length = full.length
        // Trim a trailing \n (and a preceding \r if present).
        if length > 0, ns.character(at: full.location + length - 1) == 0x0A { length -= 1 }
        if length > 0, ns.character(at: full.location + length - 1) == 0x0D { length -= 1 }
        return NSRange(location: full.location, length: length)
    }

    /// Split a spanned substring into its lines (LF), reporting whether it ended with a terminator so the
    /// rejoin can restore it without inventing or dropping a trailing newline.
    private static func splitLines(_ text: String) -> (lines: [String], trailingNewline: Bool) {
        let trailing = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if trailing { lines.removeLast() }   // drop the empty element after the final \n
        return (lines, trailing)
    }

    /// Title-case a line WITHOUT the `.capitalized` mangling: uppercase only the first letter of each
    /// space-separated word that is ENTIRELY lowercase. Preserves acronyms (`NASA`), mixed-case
    /// (`iPhone`), contractions (`don't` → `Don't`, not `Don'T`), and inline-code/marker tokens (which
    /// start with a non-letter). Splits on spaces only, keeping runs intact.
    private static func titleCased(_ line: String) -> String {
        line.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            guard !word.isEmpty, !word.contains(where: { $0.isUppercase }) else { return String(word) }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    /// The heading level of a line (count of leading `#` before a space), or 0 if it isn't a heading.
    private static func currentHeadingLevel(_ line: String) -> Int {
        let trimmed = line.drop { $0 == " " }
        var count = 0
        for ch in trimmed { if ch == "#" { count += 1 } else { break } }
        guard count >= 1, count <= 6 else { return 0 }
        let after = trimmed.dropFirst(count)
        return after.first == " " ? count : 0
    }

    /// A heading line with its `#`+ prefix (and the one following space) removed; non-headings unchanged.
    private static func strippedHeadingPrefix(_ line: String) -> String {
        guard currentHeadingLevel(line) > 0 else { return line }
        return line.replacingOccurrences(of: "^\\s*#+ ", with: "", options: .regularExpression)
    }
}
