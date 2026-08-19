---
title: Project Extraction and Reference Consumers
type: note
permalink: marker/project/project-extraction-and-reference-consumers
tags: [history, consumers]
source_paths: [Package.swift, README.md]
source_paths_inferred: false
source_sha: b48441f70845423f7ecfb76d5cad6fb1d52d557d
created: 2026-08-19
updated: 2026-08-19
reviewed: 2026-08-19
reviewed_by: audit:claude-haiku-4-5
---

## Observations
- [history] Marker born from TrapperKeeper's editor, phase 1 of extraction plan. The PURE core extracted: block parser, inline scanner, GFM tables, code-block model + language detection, block diffing, image resolution, command engine. Quote: 'Born from TrapperKeeper's editor (phase 1 of the extraction plan): the PURE core'. #extraction #extraction #history
- [decision] Phase 2 (future): MarkerEditor (TextKit 2 WYSIWYG layer) and MarkerHighlighting (tree-sitter). Kept out of core so light consumers stay dependency-free. #phased #phased #architecture
- [reference] TrapperKeeper is primary reference consumer — full-window writing app, path dependency. ShabuBox is secondary — notes pane inside larger app, versioned URL. #consumers #consumers
- [stats] 188 tests: 182 core + editor logic, 6 highlighting. Deployed in TrapperKeeper and ShabuBox. #tests #coverage
