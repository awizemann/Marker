# Marker

A reusable Markdown engine for native Swift apps — the school supply you write **Mark**down with.

## Design principle: raw-string storage

The document text is the file's exact bytes. Every model type addresses the source by range and
never mutates it; the editor styles *attributes over the raw string* instead of converting to a
rich representation. A consumer's markdown therefore round-trips **byte-exact by construction** —
there is no serializer to drift.

## Products

| Product | Contents |
|---|---|
| `Marker` | The pure engine: block parser, inline scanner, GFM pipe tables, code-block model + language detection, incremental block diffing, image path/remote resolution, document outline, and the editor state + command engine (`EditorModel`, `EditorCommands`, `EditorTool`, `CommandPaletteModel`). Foundation-level frameworks only — no AppKit, no UI. |
| `MarkerEditor` | The TextKit 2 gentle-syntax WYSIWYG layer, themed via `MarkerTheme`. Depends on the core only. |
| `MarkerHighlighting` | tree-sitter code-fence highlighting (grammars vendored), plugged into the editor via the core's `CodeTokenProviding` seam. Optional — light consumers skip the grammars entirely. |

`MarkerEditor` ships four themed components:

- **`EditorView`** — the editor itself: live WYSIWYG or raw source mode, grid tables, boxed code
  wells with hover copy, inline images, task-checkbox clicks, Cmd+click link activation.
- **`CommandPaletteView`** — the caret-anchored ⌘K-style formatting palette (drive it with the
  core's `CommandPaletteModel`; the consumer owns the trigger key and presentation).
- **`FormatBar`** — a compact persistent formatting bar over the same `EditorTool` catalog as the
  palette.
- The **wiki-link completion popup** — appears automatically while typing inside `[[…` when the
  `wikiCompletions` seam is wired; keyboard-navigable, undo-registered insertion.

## Consumer seams

App-specific behavior enters through closures and protocols — never by forking the package:

| Seam | What it does |
|---|---|
| `MarkerTheme` | Every design token the editor renders with: 10 palette colors, prose/mono/ui font families (or system-font designs like `.serif`), accent defaults. Build one from your design system. |
| `onLinkActivate` | Cmd+click on `[text](url)`, `<url>`, bare URLs, or `[[wiki links]]` — you resolve and open. |
| `wikiCompletions` | Candidates for the `[[` completion popup; you rank and cap, the editor presents. |
| `onDropFiles` | Non-image file drops → the markdown to insert at the drop caret (or nil to decline). |
| `onDropText` | Plain-string drops (dragged list rows) → a markdown replacement (or nil for default insertion). |
| `EditorModel.onDropImages` | Image drops, each with a security-scoped bookmark minted while the drop grant is live. |
| `CodeTokenProviding` | Code-fence token provider — pass `MarkerHighlighting`'s `CodeHighlighter`, your own, or nothing. |

## Requirements

Swift 6.2 (strict concurrency, MainActor default isolation), macOS 14+.

## Usage

```swift
import Marker            // pure parsing, no UI
let document = MarkdownParser.parse("# Hello\n\nSome **bold** text.")
// Each block owns a UTF-16 range of the ORIGINAL source — slices tile it exactly.
```

```swift
import MarkerEditor      // the editor with a few seams wired

@State private var editor = EditorModel(text: markdown)

EditorView(model: editor, theme: myTheme,                    // MarkerTheme from your tokens
           highlighter: CodeHighlighter.shared,              // or nil — flat mono code
           onLinkActivate: { target in openLink(target) },   // .url(String) / .wiki(String)
           wikiCompletions: { query in myCandidates(query) },
           onDropFiles: { urls in wikiLinks(for: urls) })
```

See **[docs/Integration.md](docs/Integration.md)** for the full consumer guide — choosing
products, building a theme, wiring each seam, and the raw-string invariants to respect.

Tests: 188 (182 core + editor logic, 6 highlighting). Used by
[TrapperKeeper](https://github.com/awizemann) and ShabuBox.
