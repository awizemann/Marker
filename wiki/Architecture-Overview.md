---
created: 2026-08-19
updated: 2026-08-19
---

# Architecture Overview

Marker is built on a **single founding principle**: [[marker/architecture/architecture-raw-string-storage-principle]]. The document text is the file's exact bytes. Every model type addresses it by UTF-16 range and never mutates it. This means a consumer's markdown round-trips **byte-exact by construction** — no serializer, no representation loss.

## Three-tier product design

Marker ships as three composable products, each with a clear boundary:

**Marker** (`Sources/Marker/`)
: The pure engine — Foundation-level frameworks only. Block parser, inline scanner, GFM pipe tables, code-block model with language detection, incremental block diffing, image path/remote resolution, document outline, and the editor state engine.

**MarkerEditor** (`Sources/MarkerEditor/`)
: The TextKit 2 render/edit layer, themed via `MarkerTheme`. Depends on the core only. Four components: `EditorView` (live WYSIWYG / raw source), `CommandPaletteView` (⌘K formatting), `FormatBar`, and wiki-link completion popup.

**MarkerHighlighting** (`Sources/MarkerHighlighting/`)
: Tree-sitter syntax highlighting for code fences. Plugs into the editor via the `CodeTokenProviding` seam. Optional — light consumers skip the grammars.

For details on each product, see [[marker/architecture/architecture-three-tier-product-design]].

## Core design: raw-string storage

The document is never converted to a rich representation. Instead:

- The source text is stored as exact bytes (the file on disk).
- Every block, inline, and selection is a UTF-16 range into that source.
- The editor styles *attributes over the raw text* — never converting it.
- On save, the text is written back byte-for-byte.

This design eliminates a whole class of bugs: no serializer drift, no representation loss, no precision loss on round-trip. A consumer's markdown is guaranteed to survive a read-edit-write cycle unchanged.

For the addressing scheme and UTF-16 invariants that enable this, see [[marker/conventions/text-addressing-and-utf-16-invariants]] and **[Text Storage and Addressing](Text-Storage-and-Addressing)**.

## Extension points: consumer seams

App-specific behavior enters through closures and protocols — never by forking the package. Six primary seams tie the app to Marker:

| Seam | What it does |
|---|---|
| `MarkerTheme` | Design tokens: palette colors, prose/mono/ui font families, accent defaults. Build one from your design system. |
| `onLinkActivate` | Cmd+click on a link (URL, wiki link, or bare URL) — you resolve and open. |
| `wikiCompletions` | Candidates for the `[[` completion popup; you rank and cap, the editor presents. |
| `onDropFiles` | Non-image file drops → the markdown to insert (or nil to decline). |
| `onDropText` | Plain-string drops (e.g., dragged list rows) → a markdown replacement. |
| `EditorModel.onDropImages` | Image drops with security-scoped bookmarks minted during the drop grant. |
| `CodeTokenProviding` | Code-fence tokens — pass `CodeHighlighter`, your own provider, or nil (mono). |

For the full seam reference and wiring guide, see [[marker/architecture/consumer-integration-seams]] and **[Consumer Integration](Consumer-Integration)**.

## Platform and concurrency

- **Swift 6.2** strict concurrency, MainActor default isolation.
- **macOS 14.0** floor (Observation framework + SwiftUI `onKeyPress` require 14; `@Observable` and `@Bindable` require 14).
- All async boundaries are marked. The editor model is `@MainActor Observable`; off-main work is routed through explicit isolation.

For platform specifics and MainActor defaults, see [[marker/architecture/platform-and-concurrency-settings]].

## Origin and extraction

Marker was born from [TrapperKeeper](https://github.com/awizemann)'s editor — phase 1 of an extraction plan to make the pure core reusable. The extraction preserved the raw-string invariant and MainActor isolation, so the code compiles identically in both homes.

For context, see [[marker/project/project-extraction-and-reference-consumers]].

---
_Last updated: 2026-08-19_