//
//  CodeHighlighter.swift
//  MarkerHighlighting
//
//  Tree-sitter-backed syntax highlighting for fenced code blocks (t-7def242d). It produces
//  (UTF-16 range, capture-name) tokens; the app maps each capture to a design-palette color and
//  applies it as an ATTRIBUTE over the byte-exact storage — no view ownership, no reflow, fully
//  editable in place (see decision: rich-table-and-code-block-rendering-constraints-approaches).
//
//  Range fidelity: SwiftTreeSitter parses as UTF-16LE and `Node.range` is byteRange/2, so token
//  ranges are true UTF-16 offsets into the code string — they line up with NSTextStorage exactly.
//

import Foundation
import Marker
import SwiftTreeSitter
import TreeSitterJSON
import TreeSitterTypeScript
import TreeSitterBash
import TreeSitterGo
import TreeSitterRust
import TreeSitterHTML
import CTreeSitterPython
import CTreeSitterSwift

// `HighlightToken` lives in the Marker core (Markdown/CodeHighlighting.swift) alongside the
// `CodeTokenProviding` seam this class implements, so MarkerEditor can consume tokens without
// depending on tree-sitter.

/// Produces syntax tokens for a code string in a given language. `@MainActor` because it runs inside
/// the (main-actor) editor styler and reuses one Parser/Query per language — the tree-sitter C types
/// aren't `Sendable`, so staying on main sidesteps that cleanly. Results are cached by (code,
/// language) so the per-keystroke whole-document restyle only recomputes a code block that changed.
@MainActor
public final class CodeHighlighter {
    public static let shared = CodeHighlighter()
    public init() {}

    private struct Grammar { let language: Language; let query: Query; let parser: Parser }
    private struct CacheKey: Hashable { let code: String; let language: String }

    /// Compiled grammar per canonical language. The value is `nil` for a resolved-but-unsupported /
    /// failed-to-build language, so we don't retry it every call.
    private var grammars: [String: Grammar?] = [:]
    private var cache: [CacheKey: [HighlightToken]] = [:]

    /// Tokens for `code` interpreted as `rawLanguage`. Returns `[]` for an unsupported or unparseable
    /// language (the caller then leaves the code in its flat mono style). Ranges are UTF-16 offsets
    /// into `code`.
    public func tokens(for code: String, language rawLanguage: String) -> [HighlightToken] {
        guard !code.isEmpty, let language = Self.canonicalLanguage(rawLanguage) else { return [] }
        let key = CacheKey(code: code, language: language)
        if let cached = cache[key] { return cached }
        let result = grammar(for: language).map { compute(code: code, grammar: $0) } ?? []
        if cache.count > 96 { cache.removeAll() }   // crude bound; distinct code blocks are few
        cache[key] = result
        return result
    }

    // MARK: Grammar registry

    /// Canonical language id (folding common aliases) for the grammars we ship; `nil` = unsupported.
    static func canonicalLanguage(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "json", "json5":                 return "json"
        case "javascript", "js", "jsx", "node", "mjs", "cjs": return "javascript"
        case "swift":                         return "swift"
        case "typescript", "ts", "tsx":       return "typescript"
        case "python", "py":                  return "python"
        case "bash", "sh", "shell", "zsh", "shellscript": return "bash"
        case "go", "golang":                  return "go"
        case "rust", "rs":                    return "rust"
        case "html", "htm", "xhtml":          return "html"
        default:                              return nil
        }
    }

    /// The tree-sitter parser + the base name of its vendored `queries/<name>.scm`.
    private static func grammarSource(_ language: String) -> (OpaquePointer, String)? {
        switch language {
        case "json":       return (tree_sitter_json(), "json")
        case "swift":      return (tree_sitter_swift(), "swift")
        // JavaScript is parsed by the TypeScript grammar (JS ⊂ TS) — the standalone JS grammar package
        // doesn't link as a dependency; the `typescript` query is JS+TS concatenated, so JS highlights.
        case "javascript", "typescript": return (tree_sitter_typescript(), "typescript")
        case "python":     return (tree_sitter_python(), "python")
        case "bash":       return (tree_sitter_bash(), "bash")
        case "go":         return (tree_sitter_go(), "go")
        case "rust":       return (tree_sitter_rust(), "rust")
        case "html":       return (tree_sitter_html(), "html")
        default:           return nil
        }
    }

    private func grammar(for language: String) -> Grammar? {
        if let cached = grammars[language] { return cached }   // key present (incl. cached nil)
        let built = buildGrammar(language)
        grammars[language] = built
        return built
    }

    private func buildGrammar(_ language: String) -> Grammar? {
        guard let (pointer, queryName) = Self.grammarSource(language),
              let url = Bundle.module.url(forResource: queryName, withExtension: "scm", subdirectory: "queries"),
              let data = try? Data(contentsOf: url) else { return nil }
        let tsLanguage = Language(pointer)
        guard let query = try? Query(language: tsLanguage, data: data),
              let parser = try? makeParser(tsLanguage) else { return nil }
        return Grammar(language: tsLanguage, query: query, parser: parser)
    }

    private func makeParser(_ language: Language) throws -> Parser {
        let parser = Parser()
        try parser.setLanguage(language)
        return parser
    }

    // MARK: Parse + query

    private func compute(code: String, grammar: Grammar) -> [HighlightToken] {
        guard let tree = grammar.parser.parse(code), let root = tree.rootNode else { return [] }
        let length = (code as NSString).length
        var tokens: [HighlightToken] = []
        for match in grammar.query.execute(node: root, in: tree) {
            for capture in match.captures {
                guard let name = capture.name else { continue }
                let range = capture.range
                guard range.length > 0, range.location >= 0, NSMaxRange(range) <= length else { continue }
                tokens.append(HighlightToken(range: range, capture: name))
            }
        }
        return tokens
    }
}

/// The real implementation of the Marker core's highlighting seam — MarkerEditor's styler calls
/// through `CodeTokenProviding` so it never links tree-sitter itself.
extension CodeHighlighter: CodeTokenProviding {}
