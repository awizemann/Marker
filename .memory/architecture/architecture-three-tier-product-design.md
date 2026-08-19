---
title: Architecture: Three-Tier Product Design
type: note
permalink: marker/architecture/architecture-three-tier-product-design
tags: [products, layering]
source_paths: [Package.swift, README.md]
source_paths_inferred: false
source_sha: b48441f70845423f7ecfb76d5cad6fb1d52d557d
created: 2026-08-19
updated: 2026-08-19
reviewed: 2026-08-19
reviewed_by: audit:claude-haiku-4-5
---

## Observations
- [architecture] `Marker` — pure block parser, inline scanner, GFM tables, code-block model + language detection, block diffing, image resolution, outline, editor state/command engine. Foundation-level frameworks only; no AppKit, UI, or syntax-highlighting deps. #core #core #scope
- [architecture] `MarkerEditor` — TextKit 2 WYSIWYG layer, themed via `MarkerTheme`, depends on core only. Ships `EditorView`, `CommandPaletteView`, `FormatBar`, wiki-link completion popup. #editor #editor #ui
- [architecture] `MarkerHighlighting` — tree-sitter code-fence highlighting (grammars vendored). Optional; plugs into editor via core's `CodeTokenProviding` seam. Light consumers skip. #syntax #highlighting #optional

## Relations
- relates_to [[Consumer Integration Seams]]
- relates_to [[Syntax Highlighting: Tree-Sitter Integration]]
