//
//  CodeHighlighting.swift
//  Marker — Markdown
//
//  The code-highlighting SEAM: the token vocabulary (`HighlightToken`) plus the provider protocol
//  (`CodeTokenProviding`) that lets MarkerEditor color code fences WITHOUT depending on tree-sitter.
//  MarkerHighlighting supplies the real implementation (`CodeHighlighter`); a consumer that doesn't
//  want the grammar payload simply passes no provider and code stays in its flat mono style.
//

import Foundation

/// One highlighted token: a UTF-16 range INTO the `code` string passed to `tokens(for:language:)`,
/// plus its tree-sitter capture name (e.g. "string", "number", "comment"). The caller offsets the
/// range into the editor storage and colors it — attributes only, bytes untouched.
public nonisolated struct HighlightToken: Sendable, Equatable {
    public let range: NSRange
    public let capture: String
    public init(range: NSRange, capture: String) {
        self.range = range
        self.capture = capture
    }
}

/// Produces syntax tokens for a code string in a given language. `@MainActor` because it runs inside
/// the (main-actor) editor styler. MarkerHighlighting's `CodeHighlighter` is the real implementation.
@MainActor
public protocol CodeTokenProviding: AnyObject {
    func tokens(for code: String, language: String) -> [HighlightToken]
}
