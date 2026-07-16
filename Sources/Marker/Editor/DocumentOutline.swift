//
//  DocumentOutline.swift
//  TrapperKeeperCore — Editor (P5b)
//
//  The heading outline the right-side inspector renders — a PURE derivation of the already-parsed
//  `MarkdownDocument` (no new parse, no I/O). The editor reparses on every edit, so the outline
//  updates live for free. Honest: it lists only real heading blocks, in source order, with the exact
//  source range to scroll to; a doc with no headings yields an empty outline (the view shows a quiet
//  empty state, never fabricated structure).
//
//  `nonisolated` value types (default MainActor isolation would otherwise pin these pure values).
//

import Foundation

/// One entry in the outline. `id` is the source block id (stable within a parse) so SwiftUI can key
/// rows and the active-section highlight can match; `range` is the block's source range for scroll-to.
public nonisolated struct OutlineHeading: Sendable, Equatable, Identifiable {
    public let id: Int
    /// 1...6 — the number of leading `#`.
    public let level: Int
    /// Display title: the heading text with its `#` markers (and surrounding whitespace) stripped. May
    /// be empty for a bare `##` with no text — the view renders that faintly rather than inventing text.
    public let title: String
    /// UTF-16 source range of the heading block (what the editor scrolls to).
    public let range: NSRange

    public init(id: Int, level: Int, title: String, range: NSRange) {
        self.id = id
        self.level = level
        self.title = title
        self.range = range
    }
}

public enum DocumentOutline {

    /// Every heading block, in source order, as outline entries.
    public static func headings(of document: MarkdownDocument) -> [OutlineHeading] {
        document.blocks.compactMap { block in
            guard case .heading(let level) = block.kind else { return nil }
            return OutlineHeading(id: block.id, level: level, title: title(from: block.text), range: block.range)
        }
    }

    /// The id of the heading whose SECTION contains the caret — the last heading that STARTS at or
    /// before `caret`. `nil` when the caret precedes the first heading (or the doc has none). `headings`
    /// is assumed in source order (as `headings(of:)` returns), so we can stop at the first one past the
    /// caret.
    public static func activeHeadingID(in headings: [OutlineHeading], caret: Int) -> Int? {
        var active: Int?
        for heading in headings {
            if heading.range.location <= caret { active = heading.id } else { break }
        }
        return active
    }

    /// Strip a heading line to its display title: drop leading indent + the `#` run + the space after
    /// it, then trim trailing whitespace/newline. We deliberately do NOT strip a trailing `#` run (rare
    /// ATX closing) — that risks eating a legitimate trailing `#` (e.g. "C#"), and showing the literal
    /// source is the honest fallback.
    static func title(from raw: String) -> String {
        var s = Substring(raw)
        s = s.drop(while: { $0 == " " || $0 == "\t" })   // leading indent (≤3 spaces is a valid heading)
        s = s.drop(while: { $0 == "#" })                  // the marker run
        s = s.drop(while: { $0 == " " || $0 == "\t" })    // the space(s) after the markers
        return String(s).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
