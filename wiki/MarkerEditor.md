---
created: 2026-08-19
updated: 2026-08-19
source_sha: 1736f6affa5fd5581eb381b584eafe480accbbc2
source_paths: Sources/MarkerEditor
source_paths_inferred: false
---
# MarkerEditor

The macOS editor layer (`Sources/MarkerEditor/`): a TextKit 2 `NSTextView` hosted in SwiftUI, plus
the ⌘K palette, the format bar, and wiki-link completion. Everything is themed through
`MarkerTheme` and wired to the host app through the seams described in
[Consumer Integration](Consumer-Integration). It depends on the core `Marker` product only.

## The one rule: attributes over raw bytes

The text view's storage **is** the Markdown file. Rendering never inserts, hides, or replaces
characters — it only sets attributes (font, colour, paragraph style) over ranges the core parser
reports, and draws decorations *behind* the glyphs. Syntax markers (`**`, `#`, `[ ]`) are dimmed,
painted clear, or collapsed to zero width, but the bytes and caret offsets are untouched. That is
what lets Live mode and Source mode be two views of the same storage, and why undo, selection, and
save all stay byte-exact. Background: [Text Storage and Addressing](Text-Storage-and-Addressing).

## Components

| Type | File | Role |
|---|---|---|
| `EditorView` | `EditorView.swift` | `NSViewRepresentable`. Builds the TextKit 2 stack (`NSTextContentStorage` → `NSTextLayoutManager` → `NSTextContainer` → `CodeWellTextView`), owns the coordinator that reparses/restyles on edits, routes clicks (checkbox toggles, Cmd+click links), drops, wiki completion, and the single undo-registered mutation seam `apply(_:)`. |
| `CodeWellTextView` | `CodeWellTextView.swift` | The `NSTextView` subclass. Draws the code-block **wells** (rounded, bordered boxes), the **active-line tint**, and the **task checkboxes**, all behind the text; hosts the hover-reveal copy button; handles image drag-and-drop. |
| `EditorStyler` | `EditorStyling.swift` | Turns `MarkdownBlock`s into attributes: per-block fonts/paragraph styles, inline marker dimming, code highlighting from a `CodeTokenProviding`, table styling, the `hideMarkers` / `indentHeaders` modes. Incremental: an edit restyles only the blocks the diff says changed. |
| `TableContentDelegate` / `TableGridView` | `TableSubstitution.swift`, `TableGridView.swift` | GFM pipe tables render as an editable SwiftUI grid via an `NSTextAttachment` substituted by `NSTextContentStorageDelegate`; the caret's own table flips back to raw source so it can be edited in place. |
| `CommandPaletteView` | `CommandPaletteView.swift` | The caret-anchored ⌘K formatting palette, driven by any `CommandPaletteDriving` (normally the core's `CommandPaletteModel`). |
| `FormatBar` | `FormatBar.swift` | A compact persistent toolbar over the same `EditorTool` catalog as the palette. |
| `WikiCompletionController` | `WikiCompletionController.swift` | The `[[…` completion panel — candidates from the `wikiCompletions` seam, keyboard-driven, inserts undo-registered. |
| `MarkerTheme` | `MarkerTheme.swift` | The design-token struct (below). |

## The render loop

1. `EditorModel` (core) reparses on every edit and publishes `document` (blocks as ranges) plus
   the diff of changed blocks.
2. The coordinator asks `EditorStyler` to restyle — fully on load / mode flips, incrementally on
   keystrokes (`restyleTextChange`), and just the table grid⇄raw flip on caret moves.
3. It then hands `CodeWellTextView` the geometry it draws from: `codeBlockRanges` (wells),
   `activeLineRange` (tint), `taskCheckboxes` (cells + checked state — only in Live, hide-markers,
   editable mode).
4. `CodeWellTextView.draw(_:)` paints wells → active-line tint → checkboxes, then `super.draw`
   paints the glyphs on top. Geometry comes from the layout manager's already-laid-out fragments
   (no forced layout), shared via `CodeWellGeometry` so the copy button, the tint, and the box
   always agree.

### Code wells

A fenced block gets 10 pt of paragraph spacing before its first line and after its last
(`CodeWellMetrics.spacingBefore/After`, set by the styler) — that is the air between prose and the
box. The box itself is the union of the block's *line fragments* plus 6 pt interior padding and a
10 pt horizontal inset (`CodeWellGeometry`), so it hugs the code and stays clear of neighbours even
for a block at end-of-file without a trailing newline. Fence lines are painted clear in hide-markers
mode (they still reserve their line), and the language token is coloured as a label.

### Task checkboxes

`EditorCommands.taskCheckboxCell` (core) reports the `[`…`]` cell of a task item; the styler paints
those characters clear (font untouched, so the cell keeps its width and the click target), and the
text view draws an SF Symbol over the cell's own segment rect: `checkmark.square.fill` tinted
`[onAccent, primary]` when checked, `square` (medium weight) in `checkEmpty` when empty. The same
cell geometry is what `taskCheckboxToggle` hit-tests, so drawn box and click target coincide by
construction. Boxes with stray padding (`- [ x]`) are accepted and normalised to `[x]`/`[ ]` on click.
Read-only documents show the literal text instead (nothing looks clickable that isn't).

## Theming and appearance

`MarkerTheme` is a `Sendable` **struct** of SwiftUI `Color`s and font choices — ten required palette
colours (`ink`, `inkSoft`, `muted`, `faint`, `deep`, `bright`, `primary`, `well`, `line`, `sheet`),
font families or system-font designs, and appearance-adaptive accent defaults (`highlightBackground`,
`tableZebra`, `activeLineTint`, `codeString`, `codeConstant`, `codeType`, `onAccent`, `checkEmpty`,
each exposed as `MarkerTheme.default…`). `MarkerTheme.fallback` is a system-colour placeholder until
the host injects its own.

**Light and dark need no plumbing.** Use sites convert with `NSColor(theme.x)` at style/draw time,
and a `Color` built from a dynamic `NSColor` stays dynamic through that conversion — even when stored
as an attributed-string colour (verified empirically and pinned by `AdaptiveThemeTests`). So a host
that passes adaptive colours (`MarkerTheme.adaptive(light:dark:)`, or its own
`NSColor(name:dynamicProvider:)`) gets an editor that follows the system and `.preferredColorScheme`.
The one place a colour is frozen is the checkbox symbol cache: tints are resolved under the view's
`effectiveAppearance` and the cache is keyed on appearance + resolved colours;
`viewDidChangeEffectiveAppearance` repaints the custom layers. `RenderedAppearanceTests` renders
the real view stack under `.aqua` and `.darkAqua` and samples pixels to prove it.

Design source for the dark values: the TrapperKeeper dark-mode handoff (dark is not an inversion —
accent steps up a stop, hairlines flip polarity, code wells lift off a near-black sheet). Durable
notes: [[marker/architecture/theme-appearance-adaptivity-light-dark]].

## Modes

- `isSourceMode` — raw Markdown, mono, no decorations.
- `hideMarkers` (Live) — syntax scaffolding painted clear/collapsed; checkboxes drawn; list bullets
  stay visible (they are structural).
- `indentHeaders` — whether heading text indents past its `#` run or sits flush.
- `isReadOnly` — everything selectable/copyable, no mutation, literal checkbox text.

## Headless rendering (for tests)

Three traps, all learned the hard way: setting a view's `appearance` is not enough for
`cacheDisplay(in:to:)` — wrap the render in `appearance.performAsCurrentDrawingAppearance`; the
view must live in an `NSWindow` (the checkbox cull uses `visibleRect`, empty without one); and never
set `drawsBackground` on the text view (its background is painted in `super.draw`, on top of the
wells and checkboxes — paint the sheet behind the view instead, as `EditorView` does).

## Platform

macOS 14+, TextKit 2, Swift 6 language mode with MainActor default isolation. No iOS port today
(it would need a `UITextView` host; the core is platform-neutral).

---
_Last updated: 2026-08-19_
