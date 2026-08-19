---
title: Text Addressing and UTF-16 Invariants
type: note
permalink: marker/conventions/text-addressing-and-utf-16-invariants
tags: [text-addressing, utf16, invariants]
source_paths: [docs/Integration.md]
source_paths_inferred: false
source_sha: b48441f70845423f7ecfb76d5cad6fb1d52d557d
created: 2026-08-19
updated: 2026-08-19
reviewed: 2026-08-19
reviewed_by: audit:claude-haiku-4-5
---

## Observations
- [convention] All ranges are UTF-16 offsets into the *current* text. This is the only addressing scheme in the codebase. Example from Integration.md: 'Each block owns a UTF-16 range of the ORIGINAL source — slices tile it exactly.' #addressing #utf16 #addressing
- [invariant] Anything you cache (outline entries, block ranges) is stale after any edit — re-read from `editor.document`, don't index blindly. Quote: 'Ranges are UTF-16 offsets into the current text. Anything you cache (outline entries, block ranges) is stale after any edit — re-read from editor.document, don't index blindly'. #staleness #caching #staleness
- [rule] External changes go through `load()` or full text swap — that's what resets undo and dirty baseline correctly. #external-changes #external-changes

## Relations
- extends [[Architecture: Raw-String Storage Principle]]
