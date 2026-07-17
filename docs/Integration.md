# Integrating Marker

A practical guide for consuming apps. The reference consumers are TrapperKeeper (full-window
writing app, path dependency) and ShabuBox (notes pane inside a larger app, versioned URL).

## 1. Pick your products

| You want | Link |
|---|---|
| Parse/inspect markdown, drive your own renderer, or reuse the command engine headless | `Marker` |
| The actual editor UI | `Marker` + `MarkerEditor` |
| Colored code fences in the editor | + `MarkerHighlighting` (adds vendored tree-sitter grammars; skip it and code renders in flat mono) |

`MarkerEditor` depends on the core only — the tree-sitter payload never rides along uninvited.

## 2. Build a `MarkerTheme`

Every design token the editor renders with flows through one struct — the package has no colors of
its own (only `MarkerTheme.fallback`, a placeholder until the host injects yours).

```swift
extension MarkerTheme {
    static let myApp = MarkerTheme(
        ink: DS.text1, inkSoft: DS.text2, muted: DS.text3, faint: DS.text4,
        deep: DS.brandDeep, bright: DS.brandBright, primary: DS.accent,
        well: DS.well, line: DS.line, sheet: DS.sheet,
        proseDesign: .serif)             // system serif for body text…
}
```

- **Families vs designs:** `proseFamily`/`monoFamily`/`uiFamily` resolve a bundled font *by name*;
  `proseDesign`/`uiDesign` instead pick a **system-font design** (`.serif`, `.rounded`) with no
  font files. An explicit family always wins over a design.
- **Fallbacks are total:** a nil/uninstalled family falls back to the system (or monospaced
  system) font; an unresolvable design falls back to the plain system font. A theme can never end
  up font-less.
- The six accent slots (highlight, table zebra, active-line tint, three code colors) have tuned
  defaults — override only if your palette needs it.

## 3. Host the editor

```swift
@State private var editor = EditorModel(text: "")   // create ONCE, keep alive across documents

EditorView(model: editor, theme: .myApp, highlighter: CodeHighlighter.shared)
```

Open/close documents with `editor.load(text:)` (resets caret, undo, dirty baseline) — don't
`.id()`-reset the view. Read `editor.text` for the bytes to save; call `editor.markSaved()` after
a successful write. `editor.isSourceMode` flips WYSIWYG ⇄ raw source. `editor.isFocused` is
first-responder truth for the text view — gate focus-sensitive menu key equivalents on it, not on
"an editor is on screen".

## 4. Wire the seams

App semantics enter through closures; unwired seams leave behavior byte-identical to not having
the feature.

**Links** — Cmd+click on `[text](url)`, `<url>`, bare URLs, and `[[wiki links]]`:

```swift
onLinkActivate: { target in
    switch target {
    case .url(let raw):   openURL(raw)
    case .wiki(let name): openWikiPage(named: name)
    }
}
```

**Wiki completion** — a popup while typing inside `[[…`; you rank and cap, the editor presents
verbatim and inserts undo-registered:

```swift
wikiCompletions: { query in pageTitles(matching: query, limit: 8) }
```

**File drops** — non-image file URLs, called synchronously *while the drop's sandbox grant is
live* (mint bookmarks inside the closure if you need the URLs later). Return markdown for the drop
caret, or nil to decline:

```swift
onDropFiles: { urls in urls.map { "[[\($0.deletingPathExtension().lastPathComponent)]]" }
                          .joined(separator: "\n") }
```

**Text drops** — plain-string drags (e.g. your own list rows). nil falls through to normal text
insertion:

```swift
onDropText: { string in noteID(from: string).map { "[[\(title(of: $0))]]" } }
```

**Image drops** — set on the model, not the view. Each drop carries a security-scoped bookmark
minted at drop time; persist the bytes your way, then insert + seed the rendered image:

```swift
editor.onDropImages = { drops in
    for drop in drops {
        let saved = persist(drop)                              // resolve drop.bookmark, copy bytes
        editor.addImage(url: saved.destination, data: saved.data)
        editor.insertImageReference(url: saved.destination, alt: saved.stem)
    }
}
```

`editor.setImages(_:)` seeds all of a document's image bytes after `load` (keys are the raw
`![](destination)` strings).

**Code highlighting** — pass any `CodeTokenProviding` as `highlighter:`.
`MarkerHighlighting.CodeHighlighter.shared` is the turnkey one.

## 5. The formatting trio: palette + FormatBar + shortcuts

All three surfaces execute the **same `EditorTool` catalog** (`EditorTool.cursor` /
`EditorTool.selection` — each tool is metadata around an `EditorCommand`), so they can never drift
apart:

```swift
@State private var palette = CommandPaletteModel(editor: editor)   // filterable via cursorTools:/selectionTools:

// ⌘K / ⌘/ — you own the trigger; overlay while presented (caret-anchored automatically):
if palette.isPresented { CommandPaletteView(driver: palette, theme: .myApp) }
Button("Formatting…") { palette.toggle() }.keyboardShortcut("/", modifiers: .command)

// Persistent bar, same catalog:
FormatBar(model: editor, theme: .myApp)

// Menu shortcuts, same commands:
Button("Bold") { editor.runCommand(.bold) }.keyboardShortcut("b")
```

Every mutation — commands, checkbox clicks, completions, drops — goes through one undo-registered
seam, so undo/redo always works.

## 6. Read-only mode

Set `editor.isReadOnly = true` (license lock, viewer mode): the document stays openable,
scrollable, selectable, and copyable, but typing/paste/delete are refused natively and
`runCommand` / `insertImageReference` / the drop and completion seams all no-op. The editor
doesn't know *why* it's locked — that's app policy.

## 7. The raw-string invariants (respect these)

1. **The storage is the file.** `editor.text` is the exact bytes; save it verbatim. Never
   normalize, trim, or re-serialize what the editor holds.
2. **Never mutate outside the seams.** All edits go through the editor's undo-registered path
   (typing, `runCommand`, the drop/completion closures, `insertImageReference`). Writing to the
   underlying `NSTextStorage` yourself bypasses reparse, restyle, and undo.
3. **Ranges are UTF-16 offsets into the current text.** Anything you cache (outline entries,
   block ranges) is stale after any edit — re-read from `editor.document`, don't index blindly.
4. **External changes go through `load`** (or a full text swap) — that's what resets undo and
   the dirty baseline correctly.
