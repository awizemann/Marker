//
//  MarkdownModel.swift
//  Marker — (ex TrapperKeeperCore) Markdown (P1.1)
//
//  The block model the TextKit editor styles against. A document is a sequence of blocks; each
//  block owns a contiguous UTF-16 `NSRange` of the source INCLUDING its trailing line terminator.
//  The blocks TILE the source: every unit belongs to exactly one block, and concatenating the
//  blocks' source slices reproduces the source byte-for-byte (see memory: "Editor architecture").
//
//  nonisolated value types so the parser can run off the main actor (large docs parse in the
//  background; results hop back to the text view on main).
//

import Foundation

public nonisolated enum BlockKind: Sendable, Equatable, Hashable {
    case blank
    case heading(level: Int)            // 1...6, the count of leading '#'
    case paragraph
    case blockquote                     // one or more consecutive `>` lines
    case bulletItem(marker: Character)  // '-', '*', or '+'
    case orderedItem(number: Int)       // the leading number of `1. `
    case taskItem(checked: Bool)        // `- [ ]` / `- [x]`
    case codeBlock(language: String?)   // a fenced ``` block, language from the opening fence
    case table                          // one or more consecutive `|`-delimited rows
    case thematicBreak                  // `---`, `***`, `___`
}

public nonisolated struct MarkdownBlock: Sendable, Equatable, Identifiable {
    /// Stable within a single parse (source order). Re-parsing yields the same ids for the same
    /// structure; the editor keys the cursor-line reveal off the block whose range holds the caret.
    public let id: Int
    public let kind: BlockKind
    /// UTF-16 range into the source, INCLUDING the trailing line terminator(s).
    public let range: NSRange
    /// The verbatim source slice for this block (== `(source as NSString).substring(with: range)`).
    public let text: String
    /// Leading-space count of a list item's first line (0 for every non-list block). Drives nested-list
    /// rendering — the styler indents the item by its depth. Does NOT affect tiling (ranges are unchanged).
    public let indent: Int

    public init(id: Int, kind: BlockKind, range: NSRange, text: String, indent: Int = 0) {
        self.id = id
        self.kind = kind
        self.range = range
        self.text = text
        self.indent = indent
    }
}

public nonisolated struct MarkdownDocument: Sendable, Equatable {
    public let source: String
    public let blocks: [MarkdownBlock]

    public init(source: String, blocks: [MarkdownBlock]) {
        self.source = source
        self.blocks = blocks
    }

    /// The block whose range contains `location` (a UTF-16 offset, e.g. the caret). A caret sitting
    /// exactly at a block boundary belongs to the block that STARTS there (or the last block at EOF).
    public func block(at location: Int) -> MarkdownBlock? {
        for block in blocks where NSLocationInRange(location, block.range) {
            return block
        }
        // Caret at end-of-document (== length) sits past every half-open range: use the last block.
        if location == (source as NSString).length { return blocks.last }
        return nil
    }
}
