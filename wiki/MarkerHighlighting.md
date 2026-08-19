---
created: 2026-08-19
updated: 2026-08-19
source_sha: 1736f6affa5fd5581eb381b584eafe480accbbc2
source_paths: Sources/MarkerHighlighting
source_paths_inferred: false
---
# MarkerHighlighting

Tree-sitter syntax colouring for fenced code blocks (`Sources/MarkerHighlighting/`). It plugs into
the editor through the core's `CodeTokenProviding` seam and is **optional** — a consumer that skips
it gets flat monospaced code and none of the grammar payload.

## The seam

```swift
// Sources/Marker/Markdown/CodeHighlighting.swift (core)
public protocol CodeTokenProviding: AnyObject {
    func tokens(for code: String, language: String) -> [HighlightToken]
}
public struct HighlightToken { let range: NSRange; let capture: String }   // UTF-16 range into `code`
```

`CodeHighlighter` (`Sources/MarkerHighlighting/CodeHighlighter.swift`) conforms. Pass
`CodeHighlighter.shared` (or your own provider) as `EditorView(highlighter:)`. For each fenced
block the styler asks for tokens and sets **colour attributes only** — the code bytes are untouched.

## Languages

| Fence tag(s) | Grammar | How it ships |
|---|---|---|
| `json`, `json5` | tree-sitter-json | SPM package |
| `javascript`, `js`, `jsx`, `mjs`, `cjs`, `node`; `typescript`, `ts`, `tsx` | tree-sitter-typescript (JS parsed by the TS grammar) | SPM package |
| `bash`, `sh`, `shell`, `zsh`, `shellscript` | tree-sitter-bash | SPM package |
| `go`, `golang` | tree-sitter-go | SPM package |
| `rust`, `rs` | tree-sitter-rust | SPM package |
| `html`, `htm`, `xhtml` | tree-sitter-html | SPM package |
| `swift` | tree-sitter-swift | **vendored** C target `Sources/CTreeSitterSwift` |
| `python`, `py` | tree-sitter-python | **vendored** C target `Sources/CTreeSitterPython` |

Untagged fences run through `MarkdownCodeLanguage.detect(_:)` (core) — a conservative heuristic that
recognises JSON, JS/TS, Swift, Python, Go, Rust, shell, and markup from distinctive signals and
returns nil rather than guess. Unsupported or undetected languages stay flat mono. CSS is not
shipped (grammar packaging issues under SPM).

Why Swift and Python are vendored: their upstream packages don't build cleanly as SPM dependencies
(Swift lacks a committed generated `parser.c`; Python's manifest uses relative paths that break when
consumed). Vendoring the generated `src/parser.c` + `scanner.c` into local C targets sidesteps that.
Details: [[marker/architecture/syntax-highlighting-tree-sitter-integration]].

## How tokens become colours

1. `CodeHighlighter.tokens(for:language:)` folds the fence tag to a canonical language, parses with
   the cached tree-sitter `Parser`, and runs the language's highlight `Query`; every capture becomes
   a `HighlightToken(range, capture)`.
2. `EditorStyler.syntaxColor(_:)` (`Sources/MarkerEditor/EditorStyling.swift`) maps the
   dot-hierarchical capture name to the theme, by prefix:

| Capture prefix | Theme colour |
|---|---|
| `comment` | `faint` |
| `string.special.key`, `property`, `field` | `deep` |
| `string`, `character` | `codeString` (gold) |
| `number`, `boolean`, `constant`, `float` | `codeConstant` (teal) |
| `keyword`, `operator`, `conditional`, `repeat`, `include` | `deep` |
| `function`, `method`, `constructor` | `primary` |
| `type` | `codeType` |
| `escape` | `bright` |
| `punctuation` | `muted` |

Everything else keeps the block's `inkSoft` base. All of these are appearance-adaptive when the
theme is (see [MarkerEditor](MarkerEditor) → *Theming and appearance*).

## Caching and threading

`CodeHighlighter` is `@MainActor` (tree-sitter's C types aren't `Sendable`, and it runs inside the
main-actor styler). It keeps one compiled `Grammar` (language + query + parser) per canonical
language — including a recorded *nil* for languages that failed to build, so they aren't retried — and
a `(code, language) → tokens` result cache with a crude size bound (cleared past 96 entries), so a
per-keystroke restyle only recomputes the code block that actually changed.

## Adding a language

1. Add the grammar: an SPM package dependency in `Package.swift` if it builds cleanly, otherwise a
   vendored C target like `CTreeSitterSwift` (generated `parser.c`, optional `scanner.c`, and the
   upstream `highlights.scm` + licence notice).
2. Register it in `CodeHighlighter.canonicalLanguage(_:)` (aliases → canonical id) and the grammar
   registry switch (`tree_sitter_<lang>()` + query name).
3. Optionally teach `MarkdownCodeLanguage.detect(_:)` a distinctive signal for untagged fences.
4. Add a `CodeHighlighterTests` case that asserts the captures land at the right UTF-16 ranges (the
   existing tests include an emoji case precisely to catch byte/UTF-16 slips).

---
_Last updated: 2026-08-19_
