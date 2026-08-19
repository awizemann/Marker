---
created: 2026-08-19
updated: 2026-08-19
---
# Consumer Integration

How an app embeds Marker. App-specific behaviour enters through **seams** — a theme struct and a
handful of closures/protocols — never by forking the package. The hand-maintained, authoritative
guide is `docs/Integration.md` in the repo; this page is the wiki's orientation to the same material
plus the practical lessons from the two reference consumers (TrapperKeeper, ShabuBox).

## 1. Pick your products

| You want | Depend on |
|---|---|
| Parse/inspect Markdown, drive your own renderer, or reuse the command engine headless | `Marker` |
| The actual editor UI | `Marker` + `MarkerEditor` |
| Coloured code fences | + `MarkerHighlighting` (vendored tree-sitter grammars; skip it and code renders in flat mono) |

`MarkerEditor` depends on the core only — the tree-sitter payload never rides along uninvited.

## 2. Build a `MarkerTheme`

`MarkerTheme` (`Sources/MarkerEditor/MarkerTheme.swift`) is a plain **struct** — every design token
the editor renders with. The package has no colours of its own (only `MarkerTheme.fallback`, a
system-colour placeholder until the host injects yours).

```swift
extension MarkerTheme {
    static let myApp = MarkerTheme(
        ink: DS.text1, inkSoft: DS.text2, muted: DS.text3, faint: DS.text4,
        deep: DS.brandDeep, bright: DS.brandBright, primary: DS.accent,
        well: DS.well, line: DS.line, sheet: DS.sheet,
        proseFamily: "Hanken Grotesk", monoFamily: "JetBrains Mono",   // bundled families, or…
        proseDesign: .serif)                                           // …a system-font design
}
```

**The ten core colours** (required): `ink`, `inkSoft`, `muted`, `faint` (the text ramp); `deep`,
`bright`, `primary` (the accent: `primary` drives the caret, checked boxes, and active list markers;
`deep` is accent-as-text); `well` (code wells, placeholder fills), `line` (hairlines), `sheet` (the
page). 

**Fonts:** `proseFamily` / `monoFamily` / `uiFamily` resolve a bundled font by name; `proseDesign` /
`uiDesign` pick a system-font design (`.serif`, `.rounded`) with no font files. An explicit family
wins over a design; a missing family falls back to the system (or monospaced system) font. A theme
can never end up font-less.

**Accent defaults** (optional, all appearance-adaptive, exposed as `MarkerTheme.default…`):
`highlightBackground` (`==marker pen==`), `tableZebra`, `activeLineTint`, `codeString` /
`codeConstant` / `codeType` (syntax colours), and for task boxes `onAccent` (the ✓ on a checked box)
and `checkEmpty` (an empty box's border). Override only if your palette needs it.

### Light & dark

The editor has **no appearance logic of its own** — it resolves whatever colours you hand it at draw
time. Hand it adaptive colours and it follows the system (or `.preferredColorScheme`) with no
further plumbing:

```swift
static let myApp = MarkerTheme(
    ink:   MarkerTheme.adaptive(light: 0x16241D, dark: 0xE9F1EB),
    sheet: MarkerTheme.adaptive(light: 0xFFFFFF, dark: 0x0C110E),
    well:  MarkerTheme.adaptive(light: 0x142818, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.05),
    …)
```

`MarkerTheme.adaptive(light:lightAlpha:dark:darkAlpha:)` wraps an `NSColor(name:dynamicProvider:)`
in a SwiftUI `Color`; your own dynamic `NSColor`s (asset-catalog or provider-based) work the same
way via `Color(nsColor:)`. Static colours are fine too — they just look identical in both
appearances. Two cautions: never enable `drawsBackground` on the editor's text view (paint the sheet
behind it, as `EditorView` does — the text view's own background would cover the code wells and
checkboxes), and dark is not an inversion (accent steps up a stop, hairlines flip polarity, code wells
lift off a near-black sheet). See [MarkerEditor](MarkerEditor) → *Theming and appearance*.

## 3. Host the editor

```swift
@State private var editor = EditorModel(text: "")      // create ONCE; keep alive across documents

EditorView(model: editor, theme: .myApp, highlighter: CodeHighlighter.shared)
```

- Open/close documents with `editor.load(text:)` — it resets the caret, undo, and the dirty
  baseline. Don't `.id()`-reset the view.
- Save `editor.text` verbatim; call `editor.markSaved()` after a successful write;
  `editor.hasUnsavedChanges` is the dirty flag.
- `editor.isSourceMode` flips WYSIWYG ⇄ raw source; `editor.hideMarkers` hides syntax markers in
  Live mode; `editor.isFocused` is first-responder truth for the text view — gate focus-sensitive
  menu key equivalents on it.

## 4. Wire the seams

Unwired seams leave behaviour byte-identical to not having the feature. All are parameters of
`EditorView.init` unless noted.

| Seam | Fires when | You return |
|---|---|---|
| `onLinkActivate: (MarkerLinkTarget) -> Void` | Cmd+click on `[text](url)`, `<url>`, a bare URL, or `[[wiki link]]` | — (`.url(raw)` / `.wiki(name)`) |
| `wikiCompletions: (String) -> [String]` | Typing inside `[[…` | ranked, capped candidates; the editor presents them and inserts undo-registered |
| `onDropFiles: ([URL]) -> String?` | Non-image files dropped — called synchronously while the sandbox grant is live (mint bookmarks inside) | markdown for the drop caret, or nil to decline |
| `onDropText: (String) -> String?` | Plain-string drags (e.g. your own list rows) | a markdown replacement, or nil to fall through |
| `editor.onDropImages: ([CapturedImageDrop]) -> Void` (on the **model**) | Image drops; each carries a security-scoped bookmark minted at drop time | persist, then `editor.addImage(url:data:)` + `editor.insertImageReference(url:alt:)` |
| `highlighter: CodeTokenProviding?` | Every code fence | `CodeHighlighter.shared`, your own provider, or nil for flat mono |

`editor.setImages(_:)` seeds a document's image bytes after `load` (keys are the raw `![](destination)` strings).

## 5. The formatting trio

The ⌘K palette, the `FormatBar`, and your menu shortcuts all execute the **same `EditorTool`
catalog** (`EditorTool.cursor` / `.selection` — metadata around an `EditorCommand`), so they can't
drift apart:

```swift
@State private var palette = CommandPaletteModel(editor: editor)

if palette.isPresented { CommandPaletteView(driver: palette, theme: .myApp) }   // caret-anchored
Button("Formatting…") { palette.toggle() }.keyboardShortcut("/", modifiers: .command)

FormatBar(model: editor, theme: .myApp)                                          // persistent bar
Button("Bold") { editor.runCommand(.bold) }.keyboardShortcut("b")               // menu
```

Every mutation — commands, checkbox clicks, completions, drops — goes through one undo-registered
seam (`EditorView.apply(_:)`), so undo/redo always works.

## 6. Read-only mode

`editor.isReadOnly = true` (licence lock, viewer mode): the document stays scrollable, selectable,
copyable; typing/paste/delete are refused natively; `runCommand`, `insertImageReference`, the drop
and completion seams, and checkbox clicks all no-op (and the literal `[ ]` text is shown instead of a
drawn box, so nothing looks clickable). The editor doesn't know *why* it's locked — that's app policy.

## 7. The raw-string invariants (respect these)

1. **The storage is the file.** `editor.text` is the exact bytes; save it verbatim. Never
   normalise, trim, or re-serialise what the editor holds.
2. **Never mutate outside the seams.** Writing to the underlying `NSTextStorage` yourself bypasses
   reparse, restyle, and undo.
3. **Ranges are UTF-16 offsets into the current text.** Anything you cache (outline entries, block
   ranges) is stale after any edit — re-read from `editor.document`.
4. **External changes go through `load`** (or a full text swap) — that's what resets undo and the
   dirty baseline correctly.

Background: [Text Storage and Addressing](Text-Storage-and-Addressing) and
[[marker/conventions/text-addressing-and-utf-16-invariants]].

## Lessons from the reference consumers

- **TrapperKeeper** consumes the package by local path (`../Marker`) — a TK build always runs the
  current Marker checkout, tagged or not. Handy for iteration; remember it when a TK bug report
  arrives ("which Marker is this?" → `git log` in the Marker checkout).
- **ShabuBox** pins a version tag. Each Marker release is an annotated tag plus a GitHub Release
  with notes (see [Building Marker](Building-Marker) → *Cutting a release*).
- Theme changes are source-compatible but not always visually compatible — e.g. 0.9.0 moved the
  empty checkbox from `muted` to the new `checkEmpty` token. Read the release notes before bumping.

---
_Last updated: 2026-08-19_
