---
created: 2026-08-19
updated: 2026-08-19
source_sha: 1736f6affa5fd5581eb381b584eafe480accbbc2
source_paths: Sources/Marker
source_paths_inferred: false
---

# Marker Core

The pure engine: block parsing, inline scanning, GFM tables, code-block models, image resolution, document outline, and the editor state machine. Foundation-level frameworks only — no AppKit, no UI, no external dependencies beyond Foundation and Observation.

## Block parsing and model

`MarkdownBlock` (`Sources/Marker/Markdown/MarkdownModel.swift:29`) is the core data structure. Each block is identified by its `BlockKind` (`Sources/Marker/Markdown/MarkdownModel.swift:16`) — heading, paragraph, list, code block, blockquote, table, etc. — and owns a UTF-16 range into the source text.

The parser (`MarkdownParser` — part of the public API) splits the text into blocks in a single pass. Because blocks are ranges, not copies, the storage is lean: no duplication of source text, no serializer to drift.

## Inline scanning and formatting

Inside each block, the inline scanner (`MarkdownInline`, `Sources/Marker/Markdown/MarkdownInline.swift:45`) extracts inline formatting: bold (`**`), italic (`*`), code backticks, links, images, strikethrough, and task-checkbox syntax.

`InlineSpan` (`Sources/Marker/Markdown/MarkdownInline.swift:27`) represents a single formatted run; `InlineKind` (`Sources/Marker/Markdown/MarkdownInline.swift:16`) names the kind (bold, italic, code, link, etc.).

## GFM pipe tables

GFM-style pipe tables are parsed as a block kind and represented as a structured grid. The editor can render and edit them cell-by-cell without losing the raw markdown syntax.

## Code blocks and language detection

`MarkdownCodeBlock` (`Sources/Marker/Markdown/MarkdownCodeBlock.swift:13`) holds code-block metadata: the fence delimiter, the declared language (if any), and the code text. `MarkdownCodeLanguage` (`Sources/Marker/Markdown/MarkdownCodeLanguage.swift:15`) enumerates supported languages and provides language detection by file extension or shebang.

The editor's `CodeWellTextView` (in MarkerEditor) uses this to size code wells and offer syntax highlighting — either via `CodeTokenProviding` (the seam to `MarkerHighlighting`) or flat mono.

## Image path resolution

`ImagePathResolver` (`Sources/Marker/Markdown/ImagePathResolver.swift:35`) resolves image URLs in Markdown to local or remote sources. `ImageSource` (`Sources/Marker/Markdown/ImagePathResolver.swift:16`) names the kind: local file, remote URL, or data URI.

The editor's `EditorView` uses this to load and display inline images, and respects security-scoped bookmarks for dropped images.

## Document outline

`DocumentOutline` (`Sources/Marker/Editor/DocumentOutline.swift:36`) extracts the heading hierarchy from a document. `OutlineHeading` (`Sources/Marker/Editor/DocumentOutline.swift:18`) represents a heading with its level and text.

Consumers use this to build table-of-contents UI, jump-to-heading navigation, or fold the outline into the breadcrumb.

## Editor state: EditorModel

`EditorModel` (`Sources/Marker/Editor/EditorModel.swift:29`) is the state machine for the editor. It holds:

- The source text (as-is, never mutated in place).
- Selection and caret position.
- Undo/redo history.
- Clipboard state.
- Handlers for drops, link clicks, wiki-completion queries.

The model is `@MainActor Observable`, so SwiftUI views react to state changes automatically.

## Editor commands

`EditorCommands` (`Sources/Marker/Editor/EditorCommands.swift:58`) provides a catalog of formatting operations: toggle bold/italic/code, insert/unwrap lists, toggle task checkboxes, adjust indentation, insert/remove blockquotes, toggle code-fence language, and more.

Each command is a pure function that produces a `TextEdit` (`Sources/Marker/Editor/EditorCommands.swift:19`) — a range replacement — which the editor applies to the source text.

## Command palette and tools

`CommandPaletteModel` (`Sources/Marker/Editor/CommandPalette.swift:97`) drives the ⌘K-style formatting palette. It holds the list of available `EditorToolGroup`s (`Sources/Marker/Editor/CommandPalette.swift:25`) — e.g., "Text Styles", "Lists", "Code" — and exposes a filtered/searchable view to consumers.

The consumer wires the palette trigger key (usually ⌘K) and owns the presentation logic; the model handles the catalog and filtering.

## Block diffing

`MarkdownBlockDiff` provides incremental diffing of block-level changes. Instead of recomputing the entire parse tree on every edit, the diff algorithm detects which blocks changed and updates only those — important for performance in large documents.

## Raw-string storage invariant

Every data structure — blocks, inlines, selections, edits — addresses the source by UTF-16 range. Nothing is copied or mutated in place. This invariant flows all the way through: when you apply an edit, you're replacing one range of the source with another, and the parser is re-run only on the affected block(s).

For the full addressing scheme, see [[marker/conventions/text-addressing-and-utf-16-invariants]] and **[Text Storage and Addressing](Text-Storage-and-Addressing)**.

---
_Last updated: 2026-08-19_