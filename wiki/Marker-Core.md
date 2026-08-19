---
created: 2026-08-19
updated: 2026-08-19
source_sha: 1736f6affa5fd5581eb381b584eafe480accbbc2
source_paths: Sources/Marker
source_paths_inferred: false
---
# Marker Core

The pure engine (`Sources/Marker/`): Foundation + Observation only — no AppKit, no UI, no
third-party dependencies. Everything here addresses the source text by UTF-16 range and never
rewrites it; see [Text Storage and Addressing](Text-Storage-and-Addressing). Consumers that only want
to parse, inspect, or drive their own renderer depend on this product alone.

## Block model (`Markdown/MarkdownModel.swift`, `MarkdownParser.swift`)

`MarkdownParser` splits a document into `MarkdownBlock`s in one pass. A block carries its `kind`,
its absolute `range` (UTF-16, into the source), the verbatim `text` slice, its `indent`, and an `id`
that is simply its source-order index. `BlockKind`:

`blank` · `heading(level:)` · `paragraph` · `blockquote` · `bulletItem(marker:)` ·
`orderedItem(number:)` · `taskItem(checked:)` · `codeBlock(language:)` · `table` · `thematicBreak`

Notes worth knowing:
- Task items accept whitespace-padded boxes — `- [ x]`, `- [x ]`, `- [  ]` — and are checked iff
  an `x`/`X` is present (bare `[]` stays a bullet, per GFM). The canonical shape lives in one place,
  `EditorCommands.taskBoxPattern`, shared by the parser's siblings, the styler, and the toggle.
- A fenced block is one `codeBlock` no matter what Markdown-looking text is inside; an unterminated
  fence runs to the end of the block.
- Consecutive `>` lines and consecutive `|` rows group into one block; nested list items record
  their `indent` depth.

`MarkdownDocument` holds `source` + `blocks` and answers `block(at:)` for a caret offset.
`MarkdownBlock.contentText` (`MarkdownContentText.swift`) is the marker-stripped display projection
(heading hashes, list/task markers, quote prefixes, fences removed) for consumers rendering blocks
as native views — the text and ranges stay byte-exact.

## Inline scanning (`Markdown/MarkdownInline.swift`)

`MarkdownInline.spans(in:)` finds formatted runs inside a block's text, returning `InlineSpan`s —
`kind`, the `markerRanges` to dim, the `contentRange` inside the markers, and an optional
`destinationRange` (the URL of an image). `InlineKind`: `strong`, `emphasis`, `strongEmphasis`,
`code`, `link`, `strikethrough`, `highlight` (`==`), `image`, `wikiLink` (`[[Target]]`). Ranges are
relative to the block text; patterns claim ranges in priority order (code first, so a `*` inside
backticks is never emphasis), intraword underscores don't italicise, and bare/`<url>` autolinks are
recognised.

## Tables (`Markdown/MarkdownTable.swift`)

GFM pipe tables parse into a structured grid — header, per-column alignment from the `:---:`
separator, rows padded/truncated to the header width, escaped pipes honoured, with block-relative
cell ranges so the editor can edit a cell in place. A table needs a leading pipe to be grouped as a
table block (known limitation: borderless tables are paragraphs).

## Code blocks (`Markdown/MarkdownCodeBlock.swift`, `MarkdownCodeLanguage.swift`, `CodeHighlighting.swift`)

`MarkdownCodeBlock.contentRange(inBlockText:)` addresses the code between the fences (language
token excluded). `MarkdownCodeLanguage.detect(_:)` is a conservative heuristic for untagged fences
(JSON vs JS object literal, TS vs JS, Swift, Python, Go, Rust, shell, markup) that returns nil rather
than guess. `CodeTokenProviding` / `HighlightToken` are the seam a highlighter implements — the
editor maps captures to theme colours; see [MarkerHighlighting](MarkerHighlighting).

## Block diffing (`Markdown/MarkdownBlockDiff.swift`)

`MarkdownDocument.changedBlockRange(from:)` is a front/back diff that reports the contiguous span of
blocks that *render* differently (same `kind`, `text`, `indent` ⇒ unchanged; shifted ranges and ids
are ignored). A split widens the span to both halves; a merge covers the merged block; a pure shift
is `nil`. The editor restyles only that span per keystroke.

## Images (`Markdown/ImagePathResolver.swift`)

Classifies an image destination as absolute (POSIX / `~` / `file://`), relative (resolved against the
document directory), remote (`http(s)` — never fetched in v1), or unreachable.

## Document outline (`Editor/DocumentOutline.swift`)

Heading outline derivation — level, marker-stripped title, range — plus the active heading for a
caret. Powers table-of-contents sidebars and jump-to-heading.

## Editor state: `EditorModel` (`Editor/EditorModel.swift`)

The `@MainActor @Observable` document model the editor view binds to. It owns the source `text`,
the parsed `document`, `selection` and `activeBlockID`, the mode flags (`isSourceMode`,
`hideMarkers`, `indentHeaders`, `isReadOnly`), focus (`isFocused`), the dirty flag
(`hasUnsavedChanges`, reset by `markSaved()` / `load(text:)`), in-memory image bytes
(`imageData`, `setImages`, `addImage`), and the `onDropImages` hook. It does **not** own undo —
undo/redo lives in the host text view, registered through the editor's single mutation seam.
`runCommand(_:)` and `insertImageReference(url:alt:)` are how a host mutates text programmatically.

## Commands (`Editor/EditorCommands.swift`, `EditorTool.swift`, `CommandPalette.swift`)

`EditorCommand` is the catalog: inline wraps (`bold`, `italic`, `inlineCode`, `strikethrough`,
`highlight`), `heading(n)`, line prefixes (`bulletList`, `orderedList`, `taskList`, `blockquote`),
starter blocks (`codeBlock`, `table`, `link`, `frontmatter`), line operations (`sortLines`,
`dedupeLines`, `titleCaseLines`), and side-effect commands (`copyCodeBlock`, `addImage`,
`addWebImage`). `EditorCommands` turns a command + text + selection into a `TextEdit` (range →
replacement → selection after) — pure functions, byte-precise, emoji-safe (UTF-16 offsets). It also
holds Enter-continuation for lists/quotes/tasks and the task checkbox toggle/cell geometry.

`EditorTool` wraps commands with labels/symbols/hints for UI; `EditorTool.cursor` / `.selection` are
the two catalogs. `CommandPaletteModel` (conforming to `CommandPaletteDriving`) is the state machine
behind the ⌘K palette — filtering, highlight, apply — and `FormatBarLayout` arranges the same tools
into clusters for the persistent bar.

## Tests

`Tests/MarkerTests` (195, Swift Testing): parser corpus incl. byte-exact tiling with CRLF and no
trailing newline, inline edge cases, tables, code-language detection, block diff, command mutations
(emoji offsets, read-only, EOF), wiki completion trigger math, palette state, outline, and a
performance bound on a ~6k-line parse.

---
_Last updated: 2026-08-19_
