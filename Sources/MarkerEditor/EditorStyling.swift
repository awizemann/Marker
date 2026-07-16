import AppKit
import SwiftUI
import Marker

/// Applies per-block WYSIWYG styling to the editor's text storage. The text is NEVER changed, only
/// ATTRIBUTES, so the file's bytes stay exact (see memory: "Editor architecture").
///
/// STABLE GENTLE-SYNTAX render (see decision "Retire cursor-line source reveal"): every block renders
/// the SAME whether or not the caret is in it — headings big, bold, real list bullets — with syntax
/// markers (#, **, - , > , ```, link scaffolding) kept VISIBLE but dimmed, in their in-context font, so
/// nothing reflows on focus (the old per-line raw reveal caused a caret jump). The caret's block gets
/// ONLY a soft background tint. Source mode shows the whole file raw in mono.
@MainActor
struct EditorStyler {

    /// The design tokens every color and font below resolves through (injected by the consumer).
    let theme: MarkerTheme
    /// The code-fence token provider (MarkerHighlighting's `CodeHighlighter`, or nil — code then
    /// keeps its flat mono base style).
    let highlighter: (any CodeTokenProviding)?

    init(theme: MarkerTheme, highlighter: (any CodeTokenProviding)? = nil) {
        self.theme = theme
        self.highlighter = highlighter
    }

    // MARK: Entry

    /// WYSIWYG base attributes every block starts from. Reset underline/strike too so a span that stops
    /// being a link/strike on the next parse doesn't keep a ghost decoration. Shared by the full pass
    /// and the per-block caret-move pass so they can't drift.
    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: prose(18),
            .foregroundColor: NSColor(theme.ink),
            .backgroundColor: NSColor.clear,
            .paragraphStyle: NSParagraphStyle.default,
            .underlineStyle: 0,
            .strikethroughStyle: 0,
        ]
    }

    func apply(to storage: NSTextStorage, model: EditorModel) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes(baseAttributes(), range: full)

        guard !model.isSourceMode else {
            storage.addAttribute(.font, value: mono(14), range: full)
            storage.addAttribute(.foregroundColor, value: NSColor(theme.ink), range: full)
            return
        }

        for block in model.document.blocks where block.range.length > 0 && NSMaxRange(block.range) <= storage.length {
            render(block, hideMarkers: model.hideMarkers, indentHeaders: model.indentHeaders, in: storage)
        }
        // NOTE: the current-line tint is NOT a storage attribute — CodeWellTextView draws it as an
        // overlay (see `activeLineRange`). Keeping it out of the storage means a caret move never edits
        // the text storage, so a click can't invalidate layout and clamp the scroll (t-6cfaf799).
    }

    // MARK: Incremental restyle (text edit — only the blocks that changed)

    /// Restyle after a TEXT edit. A full `apply` re-sets attributes over the ENTIRE storage, which
    /// invalidates all TextKit-2 layout — on a long document the laid-out height collapses and rebuilds
    /// lazily, so the resizable text view's frame momentarily shrinks and the scroll view clamps toward
    /// the top (the "editor jumps when you type" bug, t-6cfaf799). Instead we re-render ONLY the blocks
    /// the edit changed (a front/back block diff); unchanged blocks keep their attributes — NSTextStorage
    /// shifts them with the characters — so their layout is never touched.
    ///
    /// Correct by construction: an unchanged block renders identically (that's what `changedBlockRange`
    /// tests for), and each changed block is re-rendered exactly as a full pass would. The current-line
    /// tint isn't touched here — it's an overlay keyed off the caret, updated by the host on selection.
    func restyleTextChange(in storage: NSTextStorage, model: EditorModel, previousBlocks: [MarkdownBlock]) {
        let changed = model.document.changedBlockRange(from: previousBlocks)
        guard !model.isSourceMode else {
            restyleSourceModeChange(changed, model: model, in: storage)
            return
        }
        guard let changed else { return }
        let new = model.document.blocks
        storage.beginEditing()
        defer { storage.endEditing() }
        for i in changed where i >= 0 && i < new.count {
            renderReset(new[i], hideMarkers: model.hideMarkers, indentHeaders: model.indentHeaders, in: storage)
        }
    }

    /// Reset one block's range to the base attributes and re-render it (so a code block's well and any
    /// markers come back cleanly) — reproducing exactly what a full pass would paint for that block.
    private func renderReset(_ block: MarkdownBlock, hideMarkers: Bool, indentHeaders: Bool, in storage: NSTextStorage) {
        guard block.range.length > 0, NSMaxRange(block.range) <= storage.length else { return }
        storage.setAttributes(baseAttributes(), range: block.range)
        render(block, hideMarkers: hideMarkers, indentHeaders: indentHeaders, in: storage)
    }

    // MARK: Caret move — table grid↔raw flip only

    /// A caret move touches no storage EXCEPT when the caret enters or leaves a grid `.table`: that
    /// substitution (TableContentDelegate shows the active table as raw pipes, the rest as grids) only
    /// re-runs when the block's storage is nudged. This returns the table(s) among the blocks the caret
    /// left/entered — empty for every ordinary caret move. Split from the flip itself so the host can
    /// bracket the storage edit with scroll anchoring (the flip CHANGES the table's height, which
    /// otherwise shifts everything below it under a caret-placing click — t-6cfaf799).
    static func activeFlipTables(model: EditorModel, previous previousActiveID: Int?) -> [MarkdownBlock] {
        guard !model.isSourceMode, previousActiveID != model.activeBlockID else { return [] }
        let blocks = model.document.blocks
        let moved = [previousActiveID.flatMap { id in blocks.first { $0.id == id } }, model.activeBlock]
        return moved.compactMap { $0 }.filter { $0.kind == .table }
    }

    /// The block-level image(s) the caret left/entered — flipped between the rendered picture and raw
    /// `![alt](url)` for editing, exactly like tables. Empty for ordinary caret moves.
    static func activeFlipImages(model: EditorModel, previous previousActiveID: Int?) -> [MarkdownBlock] {
        guard !model.isSourceMode, previousActiveID != model.activeBlockID else { return [] }
        let blocks = model.document.blocks
        let moved = [previousActiveID.flatMap { id in blocks.first { $0.id == id } }, model.activeBlock]
        return moved.compactMap { $0 }.filter { $0.kind == .paragraph && MarkdownInline.soleImageSpan(in: $0.text) != nil }
    }

    /// Re-render the flipped table(s) so TableContentDelegate re-substitutes them (grid ↔ raw pipes).
    func restyleActiveTableFlip(in storage: NSTextStorage, tables: [MarkdownBlock], model: EditorModel) {
        guard !tables.isEmpty else { return }
        storage.beginEditing()
        defer { storage.endEditing() }
        for table in tables {
            renderReset(table, hideMarkers: model.hideMarkers, indentHeaders: model.indentHeaders, in: storage)
        }
    }

    /// Source mode paints the whole file raw mono; a text edit only needs the changed span re-inked to
    /// mono (the same bounded diff — never the whole document), so typing doesn't relayout everything.
    private func restyleSourceModeChange(_ changed: ClosedRange<Int>?, model: EditorModel, in storage: NSTextStorage) {
        guard let changed else { return }
        let new = model.document.blocks
        let lo = changed.lowerBound, hi = changed.upperBound
        guard lo >= 0, hi < new.count, lo <= hi else { return }
        let start = new[lo].range.location
        let end = min(NSMaxRange(new[hi].range), storage.length)
        guard end > start else { return }
        let range = NSRange(location: start, length: end - start)
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(baseAttributes(), range: range)
        storage.addAttribute(.font, value: mono(14), range: range)
        storage.addAttribute(.foregroundColor, value: NSColor(theme.ink), range: range)
    }

    // MARK: Per-block rendering (identical whether active or not)

    private func render(_ block: MarkdownBlock, hideMarkers: Bool, indentHeaders: Bool, in storage: NSTextStorage) {
        let range = block.range
        switch block.kind {
        case .heading(let level):
            let size = headingSize(level)
            storage.addAttribute(.font, value: prose(size, .bold), range: range)
            storage.addAttribute(.foregroundColor, value: NSColor(theme.ink), range: range)
            // When headers aren't indented AND markers are hidden, collapse the `#…# ` prefix to zero
            // width so the heading sits flush-left with body prose; otherwise dim/hide it in place.
            if hideMarkers && !indentHeaders {
                collapseMarker(headingPrefix(block), in: storage)
            } else {
                dimMarker(headingPrefix(block), hidden: hideMarkers, in: storage)
            }
            applyInline(block, proseSize: size, bold: true, hideMarkers: hideMarkers, in: storage)

        case .paragraph:
            storage.addAttribute(.font, value: prose(18), range: range)
            applyInline(block, proseSize: 18, hideMarkers: hideMarkers, in: storage)

        case .bulletItem, .orderedItem:
            storage.addAttribute(.paragraphStyle, value: listParagraph(depth: block.indent), range: range)
            storage.addAttribute(.font, value: prose(17), range: range)
            // List bullets/numbers are STRUCTURAL (colorMarker) — they stay visible even in hide-markers
            // mode, so a list never loses its bullets.
            colorMarker(leadingMarkerLength(block), in: block, color: theme.muted, in: storage)
            applyInline(block, proseSize: 17, hideMarkers: hideMarkers, in: storage)

        case .taskItem(let checked):
            storage.addAttribute(.paragraphStyle, value: listParagraph(depth: block.indent), range: range)
            storage.addAttribute(.font, value: prose(17), range: range)
            styleTask(block, checked: checked, in: storage)

        case .blockquote:
            storage.addAttribute(.paragraphStyle, value: quoteParagraph(), range: range)
            storage.addAttribute(.font, value: italic(18), range: range)
            storage.addAttribute(.foregroundColor, value: NSColor(theme.muted), range: range)
            for marker in lineLeadingMarkers("> ", in: block) { dimMarker(marker, hidden: hideMarkers, in: storage) }

        case .codeBlock(let language):
            storage.addAttribute(.font, value: mono(13.5), range: range)
            storage.addAttribute(.foregroundColor, value: NSColor(theme.inkSoft), range: range)  // neutral base; tokens add color
            // The grey well is drawn as a rounded, bordered BOX behind the text by CodeWellTextView
            // (an attribute can only paint a flat rect) — no `.backgroundColor` here.
            highlightCode(block, language: language, in: storage)   // color token ranges over the code text
            for fence in fenceLines(in: block) { dimMarker(fence, hidden: hideMarkers, in: storage) }
            styleCodeLanguage(block, in: storage)   // color the ```lang token as a label

        case .table:
            storage.addAttribute(.font, value: mono(13), range: range)
            storage.addAttribute(.foregroundColor, value: NSColor(theme.muted), range: range)
            styleTable(block, in: storage)

        case .thematicBreak:
            storage.addAttribute(.foregroundColor, value: NSColor(theme.faint), range: range)

        case .blank:
            break
        }
    }

    // MARK: Inline (markers dimmed, kept in-context font so nothing reflows)

    private func applyInline(_ block: MarkdownBlock, proseSize: CGFloat, bold: Bool = false, hideMarkers: Bool = false, in storage: NSTextStorage) {
        let base = block.range.location
        for span in MarkdownInline.spans(in: block.text) {
            let content = NSRange(location: base + span.contentRange.location, length: span.contentRange.length)
            guard NSMaxRange(content) <= storage.length else { continue }
            switch span.kind {
            case .strong:
                storage.addAttribute(.font, value: prose(proseSize, .bold), range: content)
            case .emphasis:
                storage.addAttribute(.font, value: bold ? italicBold(proseSize) : italic(proseSize), range: content)
            case .strongEmphasis:
                storage.addAttribute(.font, value: italicBold(proseSize), range: content)
            case .code:
                storage.addAttribute(.font, value: mono(proseSize - 3), range: content)
                storage.addAttribute(.foregroundColor, value: NSColor(theme.deep), range: content)
            case .link, .wikiLink:
                storage.addAttribute(.foregroundColor, value: NSColor(theme.primary), range: content)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: content)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
                storage.addAttribute(.foregroundColor, value: NSColor(theme.muted), range: content)
            case .highlight:
                storage.addAttribute(.backgroundColor, value: NSColor(theme.highlightBackground), range: content)
            case .image:
                break   // alt stays plain; the ![ ]( ) scaffolding dims via the marker loop below. The
                        // picture is substituted by the content-storage delegate for inactive blocks, so
                        // this raw styling only shows with the caret in the block / in Source mode.
            }
            for marker in span.markerRanges {
                let m = NSRange(location: base + marker.location, length: marker.length)
                // Strikethrough (`~~`) and highlight (`==`) markers collapse to ~0 width — the strike
                // line / highlight background already signals the span, so the text sits flush-left
                // instead of indented by the dimmed markers. Wiki-link `[[`/`]]` markers collapse the
                // same way (the primary+underline treatment already signals the link).
                // Bold/italic/code markers stay dimmed-visible.
                if span.kind == .strikethrough || span.kind == .highlight || span.kind == .wikiLink {
                    collapseMarker(m, in: storage)
                } else {
                    dimMarker(m, hidden: hideMarkers, in: storage)
                }
            }
        }
    }

    private func styleTask(_ block: MarkdownBlock, checked: Bool, in storage: NSTextStorage) {
        let prefixLen = leadingMarkerLength(block)
        colorMarker(prefixLen, in: block, color: checked ? theme.primary : theme.muted, in: storage)
        if checked {
            let bodyStart = block.range.location + prefixLen
            let bodyLen = block.range.length - prefixLen
            let body = NSRange(location: bodyStart, length: bodyLen)
            if bodyLen > 0, NSMaxRange(body) <= storage.length {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: body)
                storage.addAttribute(.foregroundColor, value: NSColor(theme.faint), range: body)
            }
        }
    }

    // MARK: Marker treatment — DIM (faint fg only; keep the font so width is stable)

    private func dimMarker(_ range: NSRange, hidden: Bool, in storage: NSTextStorage) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        // Hidden mode paints the marker CLEAR (invisible) — the chars stay in place, so the caret and
        // byte layout are untouched; only the glyphs disappear. Otherwise, gently dimmed.
        storage.addAttribute(.foregroundColor, value: hidden ? NSColor.clear : NSColor(theme.faint), range: range)
    }

    /// Collapse a marker to ~zero width: paint it clear AND shrink its font so its glyph advance goes
    /// to nothing. The characters stay in storage (bytes + caret offsets unchanged) — only their
    /// on-screen width disappears, so the following text moves flush-left. Line height is set by the
    /// block's real font (the dominant run), not this tiny one.
    private func collapseMarker(_ range: NSRange, in storage: NSTextStorage) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        storage.addAttribute(.font, value: prose(0.01), range: range)
    }

    private func colorMarker(_ length: Int, in block: MarkdownBlock, color: Color, in storage: NSTextStorage) {
        guard length > 0 else { return }
        let range = NSRange(location: block.range.location, length: min(length, block.range.length))
        guard NSMaxRange(range) <= storage.length else { return }
        storage.addAttribute(.foregroundColor, value: NSColor(color), range: range)
    }

    /// A block range minus a trailing `\n` (and a preceding `\r`), so the current-line tint doesn't
    /// paint the line break full-width.
    private func withoutTrailingNewline(_ range: NSRange, in storage: NSTextStorage) -> NSRange {
        guard range.length > 0 else { return range }
        let ns = storage.string as NSString
        var length = range.length
        if NSMaxRange(range) <= ns.length, ns.character(at: range.location + length - 1) == 0x0A { length -= 1 }
        if length > 0, ns.character(at: range.location + length - 1) == 0x0D { length -= 1 }
        return NSRange(location: range.location, length: length)
    }

    // MARK: Marker geometry

    private func headingPrefix(_ block: MarkdownBlock) -> NSRange {
        NSRange(location: block.range.location, length: headingPrefixLength(block.text))
    }

    private func headingPrefixLength(_ text: String) -> Int {
        let ns = text as NSString
        var i = 0
        while i < ns.length, ns.character(at: i) == 0x20 { i += 1 }
        while i < ns.length, ns.character(at: i) == UInt16(UInt8(ascii: "#")) { i += 1 }
        if i < ns.length, ns.character(at: i) == 0x20 { i += 1 }
        return i
    }

    /// Length of the leading list/task marker (`- `, `* `, `1. `, `- [ ] `) on the block's first line.
    private func leadingMarkerLength(_ block: MarkdownBlock) -> Int {
        let ns = block.text as NSString
        let firstLine = ns.substring(with: ns.lineRange(for: NSRange(location: 0, length: 0)))
        switch block.kind {
        case .taskItem:     return matchLength(firstLine, "^\\s*[-*+] \\[[ xX]\\] ")
        case .bulletItem:   return matchLength(firstLine, "^\\s*[-*+] ")
        case .orderedItem:  return matchLength(firstLine, "^\\s*\\d+\\. ")
        default:            return 0
        }
    }

    private func lineLeadingMarkers(_ prefix: String, in block: MarkdownBlock) -> [NSRange] {
        var result: [NSRange] = []
        let ns = block.text as NSString
        let p = prefix as NSString
        var lineStart = 0
        while lineStart < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            if lineRange.length >= p.length, ns.substring(with: NSRange(location: lineRange.location, length: p.length)) == prefix {
                result.append(NSRange(location: block.range.location + lineRange.location, length: p.length))
            }
            lineStart = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }
        return result
    }

    private func fenceLines(in block: MarkdownBlock) -> [NSRange] {
        var result: [NSRange] = []
        let ns = block.text as NSString
        var lineStart = 0
        while lineStart < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("```") {
                result.append(NSRange(location: block.range.location + lineRange.location, length: lineRange.length))
            }
            lineStart = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }
        return result
    }

    private func matchLength(_ text: String, _ pattern: String) -> Int {
        guard let r = text.range(of: pattern, options: .regularExpression) else { return 0 }
        return (text[r] as NSString).length
    }

    // MARK: Table styling (pragmatic mono — bold header, dim separator + pipes, zebra rows)

    /// Style a pipe table WITHIN the attributes-only model: the header row bold, the `|---|` separator
    /// dimmed, every `|` dimmed, and a faint zebra background on alternate data rows. We can't reflow
    /// bytes into a grid (the storage is the file), so columns line up to the extent the source pipes
    /// are padded — which is the common way people write tables.
    private func styleTable(_ block: MarkdownBlock, in storage: NSTextStorage) {
        let ns = block.text as NSString
        let base = block.range.location
        var lineStart = 0
        var headerSeen = false
        var dataRow = 0
        while lineStart < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let absolute = NSRange(location: base + lineRange.location, length: lineRange.length)
            let trimmed = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard NSMaxRange(absolute) <= storage.length, !trimmed.isEmpty else {
                lineStart = NSMaxRange(lineRange); if lineRange.length == 0 { break }; continue
            }
            if isTableSeparator(trimmed) {
                storage.addAttribute(.foregroundColor, value: NSColor(theme.faint), range: absolute)
            } else if !headerSeen {
                headerSeen = true
                storage.addAttribute(.font, value: mono(13, .bold), range: absolute)
                storage.addAttribute(.foregroundColor, value: NSColor(theme.ink), range: absolute)
            } else {
                if dataRow % 2 == 0 {
                    storage.addAttribute(.backgroundColor, value: NSColor(theme.tableZebra),
                                         range: withoutTrailingNewline(absolute, in: storage))
                }
                dataRow += 1
            }
            dimPipes(lineRange: lineRange, base: base, in: ns, storage: storage)
            lineStart = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }
    }

    /// A `|---|:--:|` alignment row: only pipes, dashes, colons, spaces — and at least one dash.
    private func isTableSeparator(_ s: String) -> Bool {
        guard s.contains("-"), s.contains("|") else { return false }
        return s.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private func dimPipes(lineRange: NSRange, base: Int, in ns: NSString, storage: NSTextStorage) {
        let pipe = UInt16(UInt8(ascii: "|"))
        for k in 0..<lineRange.length where ns.character(at: lineRange.location + k) == pipe {
            let r = NSRange(location: base + lineRange.location + k, length: 1)
            if NSMaxRange(r) <= storage.length {
                storage.addAttribute(.foregroundColor, value: NSColor(theme.faint), range: r)
            }
        }
    }

    // MARK: Fenced-code language label

    /// Color the language token on a fenced block's opening ` ```lang ` line so it reads as a label
    /// (the rest of the code keeps its mono treatment). No-op for a fence with no language.
    private func styleCodeLanguage(_ block: MarkdownBlock, in storage: NSTextStorage) {
        let ns = block.text as NSString
        let first = ns.lineRange(for: NSRange(location: 0, length: 0))
        let end = first.location + first.length
        let space = UInt16(UInt8(ascii: " ")), backtick = UInt16(UInt8(ascii: "`")), tilde = UInt16(UInt8(ascii: "~"))
        var i = first.location
        while i < end, ns.character(at: i) == space { i += 1 }
        guard i < end else { return }
        let fence = ns.character(at: i)
        guard fence == backtick || fence == tilde else { return }
        while i < end, ns.character(at: i) == fence { i += 1 }
        while i < end, ns.character(at: i) == space { i += 1 }
        var tokenEnd = i
        while tokenEnd < end, ns.character(at: tokenEnd) != 0x0A, ns.character(at: tokenEnd) != 0x0D { tokenEnd += 1 }
        guard tokenEnd > i else { return }   // no language token
        let langRange = NSRange(location: block.range.location + i, length: tokenEnd - i)
        guard NSMaxRange(langRange) <= storage.length else { return }
        storage.addAttribute(.foregroundColor, value: NSColor(theme.primary), range: langRange)
        storage.addAttribute(.font, value: mono(12, .semibold), range: langRange)
    }

    // MARK: Code syntax highlighting (provider tokens → theme palette; attributes only, bytes untouched)

    /// Syntax-color the code text of a fenced block (code = block range minus the fence lines) by
    /// mapping the token provider's tokens to the theme palette. Attributes only — code bytes stay
    /// exact and editable. No-op when no provider is wired, or for a language it doesn't support
    /// (the neutral base color remains).
    private func highlightCode(_ block: MarkdownBlock, language explicit: String?, in storage: NSTextStorage) {
        guard let highlighter else { return }   // no token provider → code keeps its flat mono style
        guard let local = MarkdownCodeBlock.contentRange(inBlockText: block.text) else { return }
        let codeText = (block.text as NSString).substring(with: local)
        // An explicit ```lang wins; a bare fence falls back to conservative content detection (nil = leave plain).
        guard let language = explicit ?? MarkdownCodeLanguage.detect(codeText) else { return }
        let base = block.range.location + local.location
        for token in highlighter.tokens(for: codeText, language: language) {
            let abs = NSRange(location: base + token.range.location, length: token.range.length)
            guard abs.location >= 0, NSMaxRange(abs) <= storage.length else { continue }
            storage.addAttribute(.foregroundColor, value: NSColor(syntaxColor(token.capture)), range: abs)
        }
    }

    /// Map a tree-sitter capture name (dot-hierarchical, e.g. "string.special.key") to a palette
    /// color, tuned for the light-grey code well. Most-specific matches first.
    private func syntaxColor(_ capture: String) -> Color {
        func has(_ prefix: String) -> Bool { capture == prefix || capture.hasPrefix(prefix + ".") }
        switch true {
        case has("comment"):                                           return theme.faint
        case has("string.special.key"), has("property"), has("field"): return theme.deep     // keys/props
        case has("string"), has("character"):                          return theme.codeString       // gold
        case has("number"), has("boolean"), has("constant"), has("float"): return theme.codeConstant // teal
        case has("keyword"), has("operator"), has("conditional"), has("repeat"), has("include"): return theme.deep
        case has("function"), has("method"), has("constructor"):       return theme.primary
        case has("type"):                                              return theme.codeType
        case has("escape"):                                            return theme.bright
        case has("punctuation"):                                       return theme.muted
        default:                                                       return theme.inkSoft
        }
    }

    // MARK: Fonts (theme families; system fallback if a family is ever missing)

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:  return 34
        case 2:  return 26
        case 3:  return 21
        case 4:  return 18
        case 5:  return 16.5
        default: return 15   // H6 — still bold, so it reads as a heading, not body
        }
    }

    private func prose(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        theme.proseNSFont(size, weight)
    }
    private func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        theme.monoNSFont(size, weight)
    }
    private func italic(_ size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(prose(size), toHaveTrait: .italicFontMask)
    }
    private func italicBold(_ size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(prose(size, .bold), toHaveTrait: .italicFontMask)
    }

    // MARK: Paragraph styles

    private func listParagraph(depth rawIndent: Int = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        // Nested lists: ~2 source spaces = one level; each level steps the whole item right by a fixed
        // amount so nesting reads consistently regardless of the (proportional) width of the source
        // spaces. Wrapped lines hang past the marker.
        let step = CGFloat(rawIndent / 2) * 18
        p.headIndent = 22 + step
        p.firstLineHeadIndent = step
        p.paragraphSpacing = 2
        return p
    }

    private func quoteParagraph() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.headIndent = 18
        p.firstLineHeadIndent = 18
        return p
    }
}
