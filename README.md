# Marker

A reusable Markdown engine for native Swift apps — the school supply you write **Mark**down with.

Marker is the pure core extracted from [TrapperKeeper](https://github.com/awizemann)'s editor:
a block parser, inline scanner, GFM pipe tables, code-block model with language detection,
incremental block diffing, image path/remote resolution, and an editor state + command engine
(`EditorModel`, `EditorCommands`, `DocumentOutline`). Foundation-level frameworks only
(Foundation, Observation, CoreGraphics) — no AppKit, no UI, no syntax-highlighting dependencies.

## Design principle: raw-string storage

The document text is the file's exact bytes. Every model type addresses the source by range and
never mutates it, so a consumer's markdown round-trips **byte-exact by construction** — there is
no serializer to drift. Rendering is the consumer's job (attributes over the raw string, in the
reference implementation).

## Products

| Product | Status | Contents |
|---|---|---|
| `Marker` | ✅ | The pure engine + 127 tests |
| `MarkerEditor` | ✅ | TextKit 2 gentle-syntax WYSIWYG editor — themes via `MarkerTheme`, depends on the core only |
| `MarkerHighlighting` | ✅ | tree-sitter code-fence highlighting, plugged into the editor via `CodeTokenProviding` (optional — light consumers skip the grammars) |

## Requirements

Swift 6.2 (strict concurrency, MainActor default isolation), macOS 26+.

## Usage

```swift
import Marker

let document = MarkdownParser.parse("# Hello\n\nSome **bold** text.")
for block in document.blocks {
    // Each block owns a UTF-16 range of the ORIGINAL source — slices tile it exactly.
}
```

Used by [TrapperKeeper](https://github.com/awizemann) and (soon) ShabuBox.
