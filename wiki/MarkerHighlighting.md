---
created: 2026-08-19
updated: 2026-08-19
source_sha: 1736f6affa5fd5581eb381b584eafe480accbbc2
source_paths: Sources/MarkerHighlighting
source_paths_inferred: false
---

# MarkerHighlighting

Tree-sitter–based syntax highlighting for code fences. Grammars are vendored in the package; highlighting is plugged into the editor via the `CodeTokenProviding` seam. Optional — light consumers skip MarkerHighlighting entirely and use flat mono code.

## CodeHighlighter: the main entry point

`CodeHighlighter` (`Sources/MarkerHighlighting/CodeHighlighter.swift:35`) is the public interface. It's initialized once (typically a shared singleton) and cached globally.

### Supported languages

- JSON (`tree-sitter-json`)
- TypeScript and JavaScript (`tree-sitter-typescript` — JS is a subset)
- Bash (`tree-sitter-bash`)
- Go (`tree-sitter-go`)
- Rust (`tree-sitter-rust`)
- HTML (`tree-sitter-html`)
- Swift (vendored into `CTreeSitterSwift` — see below)
- Python (vendored into `CTreeSitterPython` — see below)

CSS is not currently supported (grammar packaging issues in SPM).

## How it works

When you pass a code block to `CodeHighlighter.tokens(code:language:)`, it:

1. Looks up the grammar for the language (e.g., "swift" → the Swift parser).
2. Parses the code with tree-sitter.
3. Runs a hand-written query (e.g., `highlights.scm`) that captures semantic tokens — keywords, strings, function names, etc.
4. Returns an array of `HighlightToken`s, each with a byte range and a semantic kind (`"keyword"`, `"string"`, `"comment"`, etc.).

`EditorStyler` (in MarkerEditor) then maps each semantic kind to a theme color via `MarkerTheme.tokenColor(_:)`.

The result: colored code in the editor, with the styling tied to the semantic structure of the code, not just regex patterns.

## Vendored grammars: Swift and Python

SPM doesn't package Swift and Python grammars cleanly as dependencies (Swift's Package.swift has no generated `src/parser.c`; Python's relies on relative paths that fail when consumed as a dependency). We instead vendor the generated `src/parser.c` and `src/scanner.c` into two local C targets:

- **`CTreeSitterSwift`** (`Sources/Marker/Dependencies/CTreeSitterSwift/…`)
- **`CTreeSitterPython`** (`Sources/Marker/Dependencies/CTreeSitterPython/…`)

This bypasses the SPM bugs and gives us full control over the build.

Other grammars (JSON, TypeScript, Bash, Go, Rust, HTML) are pulled from SPM packages and linked directly.

## Caching and performance

`CodeHighlighter` caches both:

1. **Parsed grammars** — a `Grammar` struct holds the language parser, tree-sitter query, and compiled query state. Cached by language.
2. **Token results** — an in-memory LRU cache maps (code, language) pairs to token arrays. Prevents re-parsing the same code block.

For large documents with many code blocks, caching is critical to keep syntax highlighting responsive.

## CodeTokenProviding seam

`CodeTokenProviding` (in the core Marker package, `Sources/Marker/Markdown/CodeHighlighting.swift:28`) is the protocol that lets the editor query tokens for a code block:

```swift
public protocol CodeTokenProviding: AnyObject {
  func tokens(code: String, language: String) -> [HighlightToken]
}
```

`CodeHighlighter` conforms to this protocol. Pass it to `EditorView` and the editor will automatically query it for every code block. Consumers can also implement their own provider (e.g., a remote syntax-highlighting service).

## Integration with the editor

In `EditorView` initialization:

```swift
EditorView(model: editor, theme: myTheme,
           highlighter: CodeHighlighter.shared,  // or nil for flat mono
           …)
```

If `highlighter` is non-nil, `EditorStyler` calls `highlighter.tokens(...)` for each code block and applies the returned tokens as attributes over the code text.

If `highlighter` is nil, code blocks are rendered in a plain monospace font with no semantic coloring.

## Tree-sitter integration details

See [[marker/architecture/syntax-highlighting-tree-sitter-integration]] for the architectural details, dependency strategy, and scanner/grammar choices.

## Adding a new language

To add a new language (e.g., Ruby):

1. Add the tree-sitter Ruby grammar as an SPM dependency in `Package.swift` (if packaged nicely).
2. Add a case to the language enum in `CodeHighlighter`.
3. Write or adapt a `highlights.scm` query for the language (tree-sitter's semantic query language).
4. Test: `CodeHighlighter.tokens(code: "...", language: "ruby")`.

For languages not cleanly packaged (like Python), vendor the generated `parser.c` and `scanner.c` instead.

---
_Last updated: 2026-08-19_