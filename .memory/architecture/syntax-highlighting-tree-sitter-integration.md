---
title: Syntax Highlighting: Tree-Sitter Integration
type: note
permalink: marker/architecture/syntax-highlighting-tree-sitter-integration
tags: [highlighting, tree-sitter, dependencies]
source_paths: [Package.swift]
source_paths_inferred: false
source_sha: b48441f70845423f7ecfb76d5cad6fb1d52d557d
created: 2026-08-19
updated: 2026-08-19
reviewed: 2026-08-19
reviewed_by: audit:claude-haiku-4-5
---

## Observations
- [decision] tree-sitter for code-fence highlighting via `CodeTokenProviding` seam. Token captures mapped to theme colors as attributes over byte-exact storage. Deps: swift-tree-sitter ≥0.9.0; grammars for JSON, TypeScript, Bash, Go, Rust, HTML (all ≥0.21.0). Quote: 'tree-sitter gives (range, capture) tokens the editor maps to theme colors as attributes'. #highlighting #tree-sitter #grammars
- [decision] Python and Swift grammars NOT SPM deps — vendored locally as CTreeSitterPython and CTreeSitterSwift (generated parser.c + scanner.c). Reason: swift grammar ships no generated src/parser.c; python's Package.swift adds scanner.c via relative FileManager.fileExists that fails when consumed as dependency → undefined external-scanner symbols. #workaround #vendoring #spm-limitation
- [decision] CSS grammar dropped — same FileManager bug as python, low value for notes. JavaScript served by TypeScript grammar (JS ⊂ TS). #scope #scope
- [design] `MarkerHighlighting` is optional — light consumers skip the grammars entirely and get flat mono code. Quote: 'Optional — light consumers skip the grammars entirely'. #optional #optional #dependency-free

## Relations
- extends [[Architecture: Three-Tier Product Design]]
