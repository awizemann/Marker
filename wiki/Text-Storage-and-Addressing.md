---
created: 2026-08-19
updated: 2026-08-19
---

# Text Storage and Addressing

Marker's core design principle is **raw-string storage**: the document text is the file's exact bytes, never converted or mutated in place. Every model type addresses the source by UTF-16 range and never copies it. This is how Marker guarantees byte-exact round-tripping.

## The invariant

When a consumer loads a file, parses it with Marker, edits it, and saves it:

```
file content → parse → blocks (as ranges) → edit → save → file content (unchanged)
```

The text written back is **byte-identical** to the original. There is no serializer to drift, no representation loss.

## UTF-16 addressing

All ranges in Marker use UTF-16 offsets. This matches TextKit 2's native addressing scheme (and NSString, NSRange, etc.), so integration with the editor is seamless.

A UTF-16 offset is the position in the string counting UTF-16 code units — each Unicode code point is either 1 or 2 units (the latter for emoji and other astral planes).

### Example

```swift
let text = "Hello 👋 world"
let range = NSRange(location: 6, length: 2)  // UTF-16 offsets
let substring = (text as NSString).substring(with: range)  // "👋"
```

The emoji `👋` takes 2 UTF-16 units, so its range is [6, 8) in UTF-16 space.

For TextKit 2 integration, the text view's storage is always UTF-16, and all `NSRange` / `NSTextRange` objects use UTF-16 offsets. Marker's ranges slot into this directly.

## How blocks address the source

Each `MarkdownBlock` owns a range into the source text:

```swift
public struct MarkdownBlock: Identifiable {
  public let kind: BlockKind
  public let range: NSRange  // UTF-16 offsets
  public let inlines: [MarkdownInline]  // ranges into range
  // ...
}
```

When you parse a document, you get back an array of `MarkdownBlock`s. None of them copy the source text — they just record where in the source they live.

To get the block's text, slice the source:

```swift
let blockText = (sourceText as NSString).substring(with: block.range)
```

## How inlines address their block

Inside each block, the inline scanner finds formatting spans (bold, italic, code, links, etc.). Each `MarkdownInline` owns a range into the *block*, not the document:

```swift
let blockRange = block.range
let inlineRange = inline.range  // offset from blockRange.location

let absoluteRange = NSRange(
  location: blockRange.location + inlineRange.location,
  length: inlineRange.length
)

let inlineText = (sourceText as NSString).substring(with: absoluteRange)
```

## How edits work

When you apply an edit, you're describing a range replacement:

```swift
public struct TextEdit: Sendable, Equatable {
  public let range: NSRange      // the bytes to replace
  public let replacement: String // what to insert
}
```

Applying a `TextEdit`:

```swift
var text = "Hello world"
let edit = TextEdit(range: NSRange(0, 5), replacement: "Hi")
let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
// result == "Hi world"
```

This is what happens when you type, paste, undo, apply a command, or drop content. The model always produces a `TextEdit`, never mutates the text in place.

## How the editor displays

The TextKit 2 text view (`CodeWellTextView`) holds the source text as its backing store. When the parse tree is computed (blocks, inlines), the editor walks the tree and builds an attribute dictionary:

```
source text (immutable) ← attributes (styling) ← parse tree (blocks, inlines, ranges)
```

Every styled element (bold, italic, code color, link color, task-checkbox hit-area) is an attribute anchored to a range. Editing changes the text; the parse tree is recomputed; attributes are rebuilt.

The text itself is never *structured* — it's always raw markdown bytes. The structure lives in the attributes.

## Why this matters

**No duplication**: If you load a 10 MB file, the parse tree doesn't copy it. Blocks and inlines use ranges, not strings.

**No serializer**: When you save, you write back the original bytes. There's no step where markdown is serialized from a rich structure — a common source of drift (extra whitespace, different indentation, lost metadata).

**No representation loss**: The editor can't lose precision because there's no conversion to a rich representation. Edits are always range-based, so they round-trip exactly.

**Bidirectional editing**: Because the text is never mutated in place, you can edit in raw-source mode or WYSIWYG mode, switch between them, and the text stays coherent — both views are over the same bytes.

## Implications for consumers

When you wire a consumer seam:

- **`onDropFiles` / `onDropText`**: Return the markdown string to insert; the editor will compute the range replacement and apply it.
- **`onLinkActivate`**: You're given the link text/URL; you don't need to worry about ranges.
- **`EditorModel.onDropImages`**: Similar — describe the markdown to insert, not the range replacement.
- **Text observers**: When you observe `editor.text`, you're getting the full source, not a structured object. This is intentional — you always work with the real bytes.

## UTF-16 edge cases

The UTF-16 addressing scheme is transparent in most cases, but be aware:

- **Emoji**: Count as 2 UTF-16 units. If you're manually computing ranges, be careful.
- **Combining marks**: Some characters are combining marks (modifiers) that combine with a base character. They count as separate code units in UTF-16.
- **Mixed indentation**: Tabs and spaces are both single units. Ranges are always in code units, not visual columns.

When in doubt, use TextKit 2's APIs (which natively use UTF-16) rather than computing ranges yourself.

## For more

See [[marker/conventions/text-addressing-and-utf-16-invariants]] for the detailed invariants and the rationale behind UTF-16 addressing.

---
_Last updated: 2026-08-19_