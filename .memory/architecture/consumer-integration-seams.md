---
title: Consumer Integration Seams
type: note
permalink: marker/architecture/consumer-integration-seams
tags: [extensibility, seams, consumer-api]
source_paths: [README.md, docs/Integration.md]
source_paths_inferred: false
source_sha: b48441f70845423f7ecfb76d5cad6fb1d52d557d
created: 2026-08-19
updated: 2026-08-19
reviewed: 2026-08-19
reviewed_by: audit:claude-haiku-4-5
---

## Observations
- [pattern] App-specific behavior enters through closures and protocols, never by forking. Six primary seams: (1) `MarkerTheme` — design tokens (colors, fonts); (2) `onLinkActivate` — Cmd+click on `[text](url)`, `<url>`, bare URLs, `[[wiki links]]`; (3) `wikiCompletions` — candidates for `[[]]` popup, you rank/cap; (4) `onDropFiles` — non-image drops, return markdown or nil; (5) `onDropText` — text drags (e.g. list rows), return markdown replacement or nil; (6) `CodeTokenProviding` — code-fence token provider (or nil for flat mono). #seams #seams #extension
- [api] `EditorModel.onDropImages` — image drops with security-scoped bookmark. Minted at drop time while grant is live. Consumer persists bytes, then calls `editor.addImage()` and `editor.insertImageReference()`. #image-drops #image-handling
- [rule] Unwired seams leave behavior byte-identical to not having the feature. Every mutation (commands, clicks, completions, drops) goes through one undo-registered seam, so undo/redo always works. #consistency #default-behavior

## Relations
- relates_to [[Syntax Highlighting: Tree-Sitter Integration]]
