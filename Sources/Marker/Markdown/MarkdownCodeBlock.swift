//
//  MarkdownCodeBlock.swift
//  Marker — (ex TrapperKeeperCore) Markdown
//
//  Pure helper for the interior of a fenced `.codeBlock`: the CODE region within the block, i.e. the
//  block minus its opening and closing fence lines. Used to scope syntax highlighting to the code (not
//  the fences) and to decide what "copy code" puts on the clipboard. UTF-16/NSString throughout so
//  ranges line up with NSTextStorage.
//

import Foundation

public nonisolated enum MarkdownCodeBlock {

    /// The code region WITHIN a fenced block's verbatim text, as a block-relative UTF-16 `NSRange`:
    /// from the end of the opening fence line to the start of the closing fence line (or the block's
    /// end when the fence is unterminated). Returns nil when there's no room for code. Both ``` and ~~~
    /// fences count; a leading language token (```swift) stays on the opening fence line and is excluded.
    public static func contentRange(inBlockText blockText: String) -> NSRange? {
        let ns = blockText as NSString
        var lineStart = 0, index = 0
        var codeStart: Int?
        var closingFenceStart: Int?
        while lineStart < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let trimmed = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            if index == 0 {
                codeStart = NSMaxRange(lineRange)          // code begins after the opener
            } else if isFence {
                closingFenceStart = lineRange.location     // the LAST fence line is the closer
            }
            index += 1
            lineStart = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }
        guard let start = codeStart else { return nil }
        let end = closingFenceStart ?? ns.length           // unterminated → to the block's end
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// The code text of a fenced block (the `contentRange` substring), with trailing newlines trimmed —
    /// what "copy code" places on the clipboard. nil when the block has no code body.
    public static func codeText(inBlockText blockText: String) -> String? {
        guard let range = contentRange(inBlockText: blockText) else { return nil }
        var code = (blockText as NSString).substring(with: range)
        while code.hasSuffix("\n") || code.hasSuffix("\r") { code.removeLast() }
        return code
    }
}
