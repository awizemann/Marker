---
created: 2026-08-19
updated: 2026-08-19
source_sha: 1736f6affa5fd5581eb381b584eafe480accbbc2
source_paths: Sources/MarkerEditor
source_paths_inferred: false
---

# MarkerEditor

The TextKit 2 render/edit layer for native macOS apps. Four components — `EditorView`, `CommandPaletteView`, `FormatBar`, and wiki-link completion — all themed via `MarkerTheme` and wired with app-specific seams.

## EditorView: the editor

`EditorView` (`Sources/MarkerEditor/EditorView.swift:17`) is an `NSViewRepresentable` that embeds a `CodeWellTextView` (TextKit 2 `NSTextView` subclass) into SwiftUI. It supports:

- **Live WYSIWYG mode** — syntax highlighting, styled text, inline images, boxed code blocks with syntax colors.
- **Raw source mode** — plain markdown text, useful for bulk editing or viewing raw formatting.
- **Task-checkbox clicks** — toggle task items directly in the rendered view.
- **Link activation** — Cmd+click on `[text](url)`, `<url>`, bare URLs, or `[[wiki links]]` triggers the `onLinkActivate` seam.
- **Grid tables** — pipe tables are rendered as editable grids with cell borders.
- **Code wells** — code blocks are boxed, sized by content and declared language, with hover-triggered copy buttons.
- **Inline images** — resolved via the core's `ImagePathResolver`; dropped images get security-scoped bookmarks.
- **Drag-and-drop** — files (with `onDropFiles` seam), text (with `onDropText`), and images (with `EditorModel.onDropImages`) are handled separately.

The view takes a `MarkerTheme` (design tokens) and an optional `CodeTokenProviding` (syntax highlighter — pass `CodeHighlighter.shared` from MarkerHighlighting, or nil for flat mono).

### CodeWellTextView: the underlying TextKit 2 text view

`CodeWellTextView` (`Sources/MarkerEditor/CodeWellTextView.swift:12`) is an `NSTextView` subclass that handles:

- **Attribute attachment** — the core parse tree (blocks, inlines) is mapped to TextKit 2 attributes over the raw text (no content copy).
- **Geometry calculation** — code-well sizing (height from line count, width from the longest line, with padding).
- **Spacing metrics** — inter-paragraph, inter-list-item, code-block margins via `CodeWellMetrics` (`Sources/MarkerEditor/EditorStyling.swift:598`).
- **Task-checkbox hit-testing** — `TaskCheckbox` (`Sources/MarkerEditor/CodeWellTextView.swift:169`) geometry and click handling.

All styling is delegated to `EditorStyler` (`Sources/MarkerEditor/EditorStyling.swift:14`), which builds attributes from the `MarkerTheme` and the parsed markdown structure.

## CommandPaletteView: the ⌘K formatting palette

`CommandPaletteView` (`Sources/MarkerEditor/CommandPaletteView.swift:16`) is a SwiftUI view that presents formatting tools in a caret-anchored dropdown. It's driven by a `CommandPaletteDriving` object (typically the core's `CommandPaletteModel`), which holds the list of `EditorToolGroup`s and handles filtering/selection.

The consumer owns:
- The trigger key (usually ⌘K).
- The presentation logic (floating panel, popover, etc.).

The palette handles:
- Rendering the tool list.
- Keyboard navigation (↑/↓ to select, return to apply, escape to dismiss).
- Search filtering.

## FormatBar: persistent formatting toolbar

A compact horizontal bar of formatting buttons (bold, italic, code, lists, etc.) — same tool catalog as the palette, but always visible. Useful for users who prefer toolbar access to keyboard shortcuts.

## Wiki-link completion popup

When the user types inside `[[`, a completion popup appears with candidates from the `wikiCompletions` seam. The popup is keyboard-navigable (↑/↓ to select, return to insert, escape to dismiss) and undo-registered.

Implemented via `WikiCompletionController` and wired into the text view's input handling.

## Theming: MarkerTheme

`MarkerTheme` is a protocol that exports design tokens:

- **10 palette colors** — background, text, accent, code, etc.
- **Font families** — prose (body text), mono (code), ui (UI labels).
- **Font sizes and weights** — headings, body, code.
- **Spacing and insets** — padding, margins, line height.

Build a theme from your design system; Marker ships with a default. The editor applies the theme to every rendered element: inline formatting, code blocks, tables, task checkboxes, etc.

## Rendering and styling pipeline

1. The core `MarkdownParser` produces `MarkdownBlock`s (ranges into the source).
2. `EditorStyler` walks the parse tree and builds a TextKit 2 attribute dictionary, mapping:
   - Block kinds → paragraph styles (indentation, spacing).
   - Inline kinds → character attributes (font, color, strikethrough, etc.).
   - Code blocks → `NSTextAttachment`s (or boxed inline views).
   - Images → `NSTextAttachment`s with resolved URLs.
   - Task checkboxes → custom attributes + hit-test geometry.
3. `CodeWellTextView` applies the attributes to the underlying storage and renders.
4. On scroll, the view updates visible-range-only attributes for performance.

The source text is never copied; all styling is attribute-based, so edits are efficient and round-trip correctly.

## Syntax highlighting integration

If a `CodeTokenProviding` is passed to `EditorView` (e.g., `CodeHighlighter` from MarkerHighlighting), the editor queries it for token ranges and colors in each code block. The provider returns `HighlightToken`s (ranges + semantic kind, like "keyword" or "string"), which `EditorStyler` maps to theme colors.

For the tree-sitter integration, see [[marker/architecture/syntax-highlighting-tree-sitter-integration]] and **[MarkerHighlighting](MarkerHighlighting)**.

## Cross-platform notes

Implemented for macOS using TextKit 2, NSView, and NSTextView. iOS/iPadOS support would require a UITextView port (TextKit 1/2 over UIKit) — not currently in scope.

---
_Last updated: 2026-08-19_