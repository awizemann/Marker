---
title: Architecture: Raw-String Storage Principle
type: note
permalink: marker/architecture/architecture-raw-string-storage-principle
tags: [storage, invariant, core-principle]
source_paths: [Package.swift, README.md, docs/Integration.md]
source_paths_inferred: false
source_sha: b48441f70845423f7ecfb76d5cad6fb1d52d557d
created: 2026-08-19
updated: 2026-08-19
reviewed: 2026-08-19
reviewed_by: audit:claude-haiku-4-5
---

## Observations
- [decision] Central design principle (inherited, non-negotiable): the document text is the file's exact bytes. Every model type addresses it by range, never mutates. Consumer markdown round-trips byte-exact by construction — no serializer to drift. Quote: 'RAW-STRING STORAGE… the document text is the file's exact bytes; every model type addresses it by range and never mutates it'. #invariant #storage #round-trip
- [consequence] Editor styles attributes over raw string instead of converting to rich representation. Ranges are UTF-16 offsets into current text. Anything cached (outline, block ranges) is stale after any edit — must re-read from `editor.document`. #invariant #addressing #freshness
- [rule] Never mutate outside the seams. All edits go through undo-registered path (typing, `runCommand`, drop/completion closures, `insertImageReference`). Writing to NSTextStorage directly bypasses reparse, restyle, undo. #invariant #mutation #undo
- [rule] External changes go through `load()` — resets undo and dirty baseline correctly. Never normalize, trim, or re-serialize what editor holds. #invariant #external-changes

## Relations
- extends [[Text Addressing and UTF-16 Invariants]]
