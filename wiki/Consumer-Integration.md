---
created: 2026-08-19
updated: 2026-08-19
---

# Consumer Integration

Marker is designed to integrate into macOS apps via **consumer seams** — closures and protocols that plug app-specific behavior into the engine without requiring a fork of the package.

This page walks through wiring each seam and common integration patterns. For the full API reference, see `docs/Integration.md`.

## Quick start

```swift
import Marker
import MarkerEditor

// 1. Create an editor model
@State private var editor = EditorModel(text: myMarkdown)

// 2. Build a theme from your design system
let theme = MyMarkerTheme()

// 3. Wire the editor view
EditorView(
  model: editor,
  theme: theme,
  highlighter: CodeHighlighter.shared,
  onLinkActivate: { target in myApp.openLink(target) },
  wikiCompletions: { query in myApp.searchWikiPages(query) },
  onDropFiles: { urls in myApp.wikiLinks(for: urls) }
)
```

## Seam reference

### MarkerTheme: design tokens

`MarkerTheme` is a protocol you implement to export design tokens:

```swift
public protocol MarkerTheme {
  // Colors
  var backgroundColor: Color { get }
  var textColor: Color { get }
  var accentColor: Color { get }
  var codeBackgroundColor: Color { get }
  // ... (10 colors total)
  
  // Fonts
  var proseFamily: Font.Design { get }  // .default, .serif, etc.
  var monoFamily: Font.Design { get }
  var uiFamily: Font.Design { get }
  
  // Sizes and weights
  var bodySize: CGFloat { get }
  var headingWeight: Font.Weight { get }
  // ... (more metrics)
}
```

Build your theme once and pass it to every `EditorView` instance:

```swift
let theme = MyMarkerTheme()  // implements the protocol
EditorView(model: editor, theme: theme, ...)
```

The editor applies the theme to every element: headings, code blocks, tables, task checkboxes, inline formatting.

### onLinkActivate: handle link clicks

When the user Cmd+clicks on a link in the editor, the `onLinkActivate` closure is called:

```swift
onLinkActivate: { target in
  switch target {
  case .url(let url):
    NSWorkspace.shared.open(URL(string: url))
  case .wiki(let pageName):
    myApp.navigateToWikiPage(pageName)
  }
}
```

`MarkerLinkTarget` (`Sources/MarkerEditor/EditorView.swift:8`) names the kind: `.url(String)` for `[text](url)`, `<url>`, and bare URLs, or `.wiki(String)` for `[[wiki links]]`.

### wikiCompletions: suggest wiki pages

When the user types `[[`, a completion popup appears. The `wikiCompletions` closure is called with the query (text after `[[`):

```swift
wikiCompletions: { query in
  let candidates = myApp.allWikiPages()
    .filter { $0.title.lowercased().contains(query.lowercased()) }
    .prefix(10)  // cap at 10
  return Array(candidates)
}
```

Return an array of `WikiCompletionCandidate`s (or whatever your app's wiki type is). The editor renders them in the popup; the user selects with arrow keys and return.

### onDropFiles: insert markdown for dropped files

When a non-image file is dropped into the editor, `onDropFiles` is called:

```swift
onDropFiles: { urls in
  let links = urls.map { url in
    "[\(url.lastPathComponent)](file://\(url.path))"
  }
  return links.joined(separator: "\n")  // or nil to reject
}
```

Return the markdown string to insert at the drop caret, or nil to decline the drop.

### onDropText: insert markdown for dragged text

When plain text is dragged (e.g., a list item from your app), `onDropText` is called:

```swift
onDropText: { droppedText in
  // Dragged text might be a row from a table; convert to markdown
  return "- \(droppedText)"  // or nil for default insertion
}
```

Return a markdown string, or nil to use default insertion (the text as-is).

### EditorModel.onDropImages: handle dropped images

When an image is dropped, security-scoped bookmarks are minted and passed to this closure:

```swift
editor.onDropImages = { drops in
  for drop in drops {
    // drop.bookmark is a Data containing a security-scoped bookmark
    // drop.url is the original file URL
    
    let imagePath = myApp.saveImage(drop.url, bookmark: drop.bookmark)
    let markdown = "![\(drop.filename)](\(imagePath))"
    
    editor.insertMarkdown(markdown, at: selectedRange)
  }
}
```

`CapturedImageDrop` (`Sources/Marker/Editor/EditorModel.swift:38`) holds the URL and bookmark. Use the bookmark to access the file after the drop grant expires.

### CodeTokenProviding: syntax highlighting

If you want code-fence syntax highlighting, pass a `CodeTokenProviding` object:

```swift
EditorView(
  model: editor,
  theme: theme,
  highlighter: CodeHighlighter.shared,  // MarkerHighlighting's provider
  ...
)
```

Or nil for flat mono code:

```swift
EditorView(
  model: editor,
  theme: theme,
  highlighter: nil,  // no syntax coloring
  ...
)
```

Implement your own provider by conforming to the protocol:

```swift
class MyHighlighter: CodeTokenProviding {
  func tokens(code: String, language: String) -> [HighlightToken] {
    // Fetch tokens from your service, local cache, etc.
    // Return an array of HighlightToken (range + semantic kind)
  }
}
```

## Common patterns

### Persisting edits

`EditorModel` is `@Observable`, so changes propagate automatically to SwiftUI views:

```swift
@State private var editor = EditorModel(text: myMarkdown)

// Whenever the user edits, editor.text changes
// You can observe it:

.onChange(of: editor.text) { newText in
  mySaver.save(newText, to: myFile)  // async, debounced, etc.
}
```

### Undo/redo

`EditorModel` maintains undo/redo stacks. The user presses ⌘Z and ⌘⇧Z to undo/redo:

```swift
// Manual undo/redo (if your app has custom UI)
editor.undo()
editor.redo()
```

### Switching between WYSIWYG and raw source

`EditorView` supports both modes. You can toggle via a toolbar button and `@State`:

```swift
@State private var showRawSource = false

EditorView(model: editor, theme: theme, showRawSource: showRawSource, ...)
```

### Image path resolution

Images in markdown can be relative paths, absolute paths, URLs, or data URIs. `ImagePathResolver` (in Marker core) handles the lookup:

```swift
let imageURL = ImagePathResolver.resolve(
  imagePath: "images/screenshot.png",
  relativeTo: myDocumentURL  // base for relative paths
)

if let imageURL = imageURL, case .local(let fileURL) = imageURL {
  // Load the image from fileURL
}
```

## Security and sandboxing

When an image or file is dropped from outside your app's sandbox, macOS grants a temporary access right via a **security-scoped bookmark**. Marker automatically mints these and passes them to your drop handlers.

Use the bookmark to re-open the file later:

```swift
// At drop time
let bookmarkData = ...  // from the drop handler
try bookmarkData.securityScopedURL { url in
  // Now you can read from url
  let data = try Data(contentsOf: url)
}
```

## Integration checklist

- [ ] Import `Marker` and `MarkerEditor`.
- [ ] Create an `EditorModel` with your markdown text.
- [ ] Implement `MarkerTheme` from your design system.
- [ ] Wire `onLinkActivate` to your link-handling logic.
- [ ] Wire `wikiCompletions` to your wiki-page search (or empty list if no wiki).
- [ ] Wire `onDropFiles` and `onDropText` (or use nil for default behavior).
- [ ] Pass `CodeHighlighter.shared` for syntax highlighting, or nil for mono.
- [ ] Observe `editor.text` with `.onChange` to persist edits.
- [ ] Test link clicks, completions, drops, and undo/redo.

---
_Last updated: 2026-08-19_