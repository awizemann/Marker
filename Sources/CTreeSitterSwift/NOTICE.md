# Vendored tree-sitter grammar C sources

`Sources/CTreeSitterSwift` and `Sources/CTreeSitterPython` are local C targets that vendor a
tree-sitter grammar's generated parser so we can syntax-highlight Swift and Python code blocks.
We vendor (rather than depend on the grammar's SPM package) because neither links cleanly as a
dependency:

- **Swift** (`alex-pinkus/tree-sitter-swift`, MIT) ships no generated `src/parser.c` — it runs
  `tree-sitter generate` at build time, which SPM won't do for a dependency. `src/parser.c` here was
  generated with `tree-sitter-cli` 0.24 from that repo's `grammar.js` (ABI/LANGUAGE_VERSION 14,
  compatible with the swift-tree-sitter 0.25 runtime we link).
- **Python** (`tree-sitter/tree-sitter-python`, MIT) ships `src/parser.c` but its `Package.swift`
  adds `src/scanner.c` via a RELATIVE `FileManager.fileExists` check that evaluates against the
  consumer's root when used as a dependency, so the external scanner never links (undefined symbols).
  Vendoring the sources into a target we control lists `scanner.c` unconditionally.

Each target mirrors the upstream layout: `src/parser.c` + `src/scanner.c`, private headers under
`src/tree_sitter/`, and a public `tree_sitter_<lang>()` declaration under `include/`. The matching
`queries/highlights.scm` is vendored under `Sources/MarkerHighlighting/Resources/queries/` (see that README).

**To update:** re-run `tree-sitter generate` (Swift) or re-copy `src/{parser,scanner}.c` +
`src/tree_sitter/*.h` from the upstream checkout, and re-copy `highlights.scm`. Both upstreams are MIT
licensed; the generated parser tables are derived works of the MIT-licensed grammars.
