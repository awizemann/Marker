import Testing
import Foundation
import Marker
@testable import MarkerHighlighting

@MainActor
@Suite("Code highlighter")
struct CodeHighlighterTests {

    /// Capture names of tokens intersecting the first occurrence of `sub` in `code`.
    private func captures(_ tokens: [HighlightToken], coveringFirst sub: String, in code: String) -> [String] {
        let r = (code as NSString).range(of: sub)
        guard r.location != NSNotFound else { return [] }
        return tokens.filter { NSIntersectionRange($0.range, r).length > 0 }.map(\.capture)
    }

    @Test("JSON: strings, numbers, and booleans get their tree-sitter captures at the right ranges")
    func jsonTokens() {
        let code = "{\n  \"name\": \"Ada\",\n  \"age\": 36,\n  \"ok\": true\n}\n"
        let tokens = CodeHighlighter().tokens(for: code, language: "json")
        #expect(!tokens.isEmpty)
        #expect(captures(tokens, coveringFirst: "\"Ada\"", in: code).contains { $0.hasPrefix("string") })
        #expect(captures(tokens, coveringFirst: "36", in: code).contains { $0.hasPrefix("number") })
        #expect(captures(tokens, coveringFirst: "true", in: code).contains { $0.hasPrefix("constant") })
        // DISCRIMINATION: fails if the grammar isn't wired (no tokens), the query resource didn't load
        // from Bundle.module, or ranges don't line up with the source substrings.
    }

    @Test("token ranges are UTF-16 offsets — a surrogate-pair emoji does not shift them")
    func utf16Ranges() {
        // 😀 is one UTF-16 surrogate pair (length 2) but 4 UTF-8 bytes. The string value's token must
        // still land EXACTLY on the quoted value.
        let code = "{\"e\": \"😀x\"}"
        let tokens = CodeHighlighter().tokens(for: code, language: "json")
        let valueRange = (code as NSString).range(of: "\"😀x\"")
        #expect(tokens.contains { NSEqualRanges($0.range, valueRange) && $0.capture.hasPrefix("string") })
        // DISCRIMINATION: if ranges were UTF-8 byte offsets, the emoji (4 bytes vs 2 UTF-16 units)
        // would push this token right and the exact-range match fails — the classic tree-sitter/AppKit
        // off-by-N that would be lethal to a byte-exact editor.
    }

    @Test("each shipped language builds its grammar + query and matches a representative snippet")
    func eachLanguageProducesTokens() {
        let cases: [(String, String)] = [
            ("swift",      "let x = 1  // note\n"),      // vendored local C target (CTreeSitterSwift)
            ("javascript", "const x = 1\n"),            // routed to the TS grammar (JS ⊂ TS)
            ("typescript", "const x: number = 1\n"),    // proves the JS+TS concatenated query compiles
            ("python",     "def f():\n    return 1\n"),  // vendored local C target (CTreeSitterPython)
            ("bash",       "echo \"hi\"\n"),
            ("go",         "package main\n"),
            ("rust",       "fn main() {}\n"),
            ("html",       "<div>hi</div>\n"),
            ("json",       "{\"a\": 1}\n"),
        ]
        let hl = CodeHighlighter()
        for (lang, code) in cases {
            #expect(!hl.tokens(for: code, language: lang).isEmpty, "no tokens for \(lang)")
        }
        // DISCRIMINATION: a wrong product/C-function name, a query that fails to compile against the
        // grammar, an ABI mismatch, or a missing vendored .scm all surface as empty tokens for that
        // named language — this is the guard that the whole multi-grammar wiring actually works.
    }

    @Test("common language aliases resolve (js/ts/sh/rs)")
    func aliases() {
        let hl = CodeHighlighter()
        #expect(!hl.tokens(for: "const x = 1\n", language: "js").isEmpty)
        #expect(!hl.tokens(for: "const x = 1\n", language: "ts").isEmpty)
        #expect(!hl.tokens(for: "echo hi\n", language: "sh").isEmpty)
        #expect(!hl.tokens(for: "fn main() {}\n", language: "rs").isEmpty)
        // DISCRIMINATION: fails if the alias table doesn't fold to the canonical grammar id.
    }

    @Test("an unsupported language yields no tokens (caller keeps the flat mono style)")
    func unsupportedLanguage() {
        #expect(CodeHighlighter().tokens(for: "SELECT 1", language: "cobol").isEmpty)
        #expect(CodeHighlighter().tokens(for: "{}", language: "").isEmpty)
        // DISCRIMINATION: fails if an unknown language throws or returns garbage instead of the empty
        // fallback the styler relies on.
    }

    @Test("repeated calls for the same (code, language) are stable")
    func deterministic() {
        let hl = CodeHighlighter()
        let code = "{\"a\": 1, \"b\": [true, null]}"
        #expect(hl.tokens(for: code, language: "json") == hl.tokens(for: code, language: "json"))
        // Also proves the cache path returns an equal result, not a corrupted/emptied one on 2nd hit.
    }
}
