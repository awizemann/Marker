# Vendored tree-sitter highlight queries

Each `<language>.scm` here is a tree-sitter **highlights** query copied from that language's grammar
repository, loaded at runtime via `Bundle.module` and compiled against the grammar's parser by
`CodeHighlighter`.

We vendor these (rather than read each grammar package's own resource bundle) so query loading is
identical under `swift test` and the xcodebuild app, and so we can curate them (e.g. `typescript.scm`
is JavaScript + TypeScript concatenated, since `SwiftTreeSitter` does not resolve the `; inherits:`
directive tree-sitter's CLI uses).

When bumping a grammar's SPM version (or a vendored C target), re-copy its `queries/highlights.scm`
here so the query stays compatible with the parser's node types.

| file | source (queries/highlights.scm) | licence |
|------|--------|---------|
| json.scm | tree-sitter/tree-sitter-json (SPM dep) | MIT |
| typescript.scm | tree-sitter/tree-sitter-javascript + tree-sitter-typescript (SPM dep, concatenated) | MIT |
| bash.scm | tree-sitter/tree-sitter-bash (SPM dep) | MIT |
| go.scm | tree-sitter/tree-sitter-go (SPM dep) | MIT |
| rust.scm | tree-sitter/tree-sitter-rust (SPM dep) | MIT |
| html.scm | tree-sitter/tree-sitter-html (SPM dep) | MIT |
| python.scm | tree-sitter/tree-sitter-python (vendored — see Sources/CTreeSitterPython) | MIT |
| swift.scm | alex-pinkus/tree-sitter-swift (vendored — see Sources/CTreeSitterSwift) | MIT |

**JavaScript** is served by the TypeScript grammar (JS ⊂ TS), so there is no separate `javascript.scm`.

**Vendored grammars.** swift + python are compiled from generated C in local targets
(`Sources/CTreeSitter{Swift,Python}`) instead of SPM deps, because their grammar packages don't link
cleanly as dependencies (swift ships no generated `parser.c`; python's `Package.swift` omits
`scanner.c` via a relative `fileExists` check). See `Sources/CTreeSitterSwift/NOTICE.md`. **css**
remains dropped (same fileExists bug, low value for notes).
