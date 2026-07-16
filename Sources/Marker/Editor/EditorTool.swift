//
//  EditorTool.swift
//  Marker — (ex TrapperKeeperCore) Editor (P4.2)
//
//  The ⌘K palette's menu: each tool is a labeled `EditorCommand`. Two toolsets — one for a bare caret
//  (insert/format), one for an active selection (wrap / turn-into / operate-on-lines) — mirroring
//  design/INTERACTIONS.md "Command-K". Tools whose commands aren't in the P4 engine (math, mermaid,
//  footnote, jump-to-heading, open-file) are deliberately omitted.
//

import Foundation

public nonisolated struct EditorTool: Identifiable, Sendable, Equatable {
    /// Stable key (also the SwiftUI list id).
    public let id: String
    public let label: String
    public let symbol: String
    public let hint: String
    /// Section header in the palette (preserves list order).
    public let group: String
    public let command: EditorCommand

    public init(id: String, label: String, symbol: String, hint: String = "", group: String, command: EditorCommand) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.hint = hint
        self.group = group
        self.command = command
    }

    /// Shown when the caret is bare — insert/format at the cursor.
    public static let cursor: [EditorTool] = [
        .init(id: "h1",          label: "Heading 1",   symbol: "H1",  hint: "#",   group: "Format", command: .heading(1)),
        .init(id: "h2",          label: "Heading 2",   symbol: "H2",  hint: "##",  group: "Format", command: .heading(2)),
        .init(id: "h3",          label: "Heading 3",   symbol: "H3",  hint: "###", group: "Format", command: .heading(3)),
        .init(id: "bold",        label: "Bold",        symbol: "B",   hint: "⌘B",  group: "Format", command: .bold),
        .init(id: "italic",      label: "Italic",      symbol: "I",   hint: "⌘I",  group: "Format", command: .italic),
        .init(id: "code",        label: "Inline code", symbol: "</>", hint: "`",   group: "Format", command: .inlineCode),
        .init(id: "strike",      label: "Strikethrough", symbol: "S", hint: "~~",  group: "Format", command: .strikethrough),
        .init(id: "highlight",   label: "Highlight",   symbol: "▮",   hint: "==",  group: "Format", command: .highlight),
        .init(id: "ul",          label: "Bullet list", symbol: "•",                group: "Insert", command: .bulletList),
        .init(id: "ol",          label: "Numbered list", symbol: "1.",             group: "Insert", command: .orderedList),
        .init(id: "task",        label: "Task list",   symbol: "☑",                group: "Insert", command: .taskList),
        .init(id: "quote",       label: "Block quote", symbol: "❝",                group: "Insert", command: .blockquote),
        .init(id: "codeblock",   label: "Code block",  symbol: "{ }", hint: "```", group: "Insert", command: .codeBlock),
        .init(id: "table",       label: "Table",       symbol: "▦",                group: "Insert", command: .table),
        .init(id: "link",        label: "Link",        symbol: "↗",                group: "Insert", command: .link),
        .init(id: "image",       label: "Add image",   symbol: "▨",                group: "Insert", command: .addImage),
        .init(id: "webimage",    label: "Add web image", symbol: "◱", hint: "url", group: "Insert", command: .addWebImage),
        .init(id: "frontmatter", label: "Frontmatter", symbol: "≣",   hint: "---", group: "Insert", command: .frontmatter),
    ]

    /// Shown when text is selected — wrap / turn-into / operate-on-lines.
    public static let selection: [EditorTool] = [
        .init(id: "bold",      label: "Bold",          symbol: "B",   hint: "⌘B", group: "Wrap selection",     command: .bold),
        .init(id: "italic",    label: "Italic",        symbol: "I",   hint: "⌘I", group: "Wrap selection",     command: .italic),
        .init(id: "code",      label: "Inline code",   symbol: "</>", hint: "`",  group: "Wrap selection",     command: .inlineCode),
        .init(id: "strike",    label: "Strikethrough", symbol: "S",   hint: "~~", group: "Wrap selection",     command: .strikethrough),
        .init(id: "highlight", label: "Highlight",     symbol: "▮",   hint: "==", group: "Wrap selection",     command: .highlight),
        .init(id: "link",      label: "Make a link",   symbol: "↗",               group: "Wrap selection",     command: .link),
        .init(id: "toh1",      label: "Heading 1",     symbol: "H1",              group: "Turn selection into", command: .heading(1)),
        .init(id: "toh2",      label: "Heading 2",     symbol: "H2",              group: "Turn selection into", command: .heading(2)),
        .init(id: "toh3",      label: "Heading 3",     symbol: "H3",              group: "Turn selection into", command: .heading(3)),
        .init(id: "toblock",   label: "Code block",    symbol: "{ }", hint: "```", group: "Turn selection into", command: .codeBlock),
        .init(id: "tolist",    label: "Bullet list",   symbol: "•",               group: "Turn selection into", command: .bulletList),
        .init(id: "toorder",   label: "Numbered list", symbol: "1.",              group: "Turn selection into", command: .orderedList),
        .init(id: "totask",    label: "Task list",     symbol: "☑",               group: "Turn selection into", command: .taskList),
        .init(id: "totable",   label: "Table",         symbol: "▦",               group: "Turn selection into", command: .table),
        .init(id: "toquote",   label: "Block quote",   symbol: "❝",               group: "Turn selection into", command: .blockquote),
        .init(id: "sort",      label: "Sort lines A→Z", symbol: "↕",              group: "Operate on lines",   command: .sortLines),
        .init(id: "dedupe",    label: "Remove duplicates", symbol: "⊟",           group: "Operate on lines",   command: .dedupeLines),
        .init(id: "titlecase", label: "To Title Case", symbol: "Aa",              group: "Operate on lines",   command: .titleCaseLines),
    ]

    /// A contextual action the host appends to `activeTools` ONLY when the caret sits in a code block:
    /// copy that block's code to the clipboard. Lives in the palette so it's discoverable and
    /// VoiceOver-reachable (the mouse-only hover button isn't) — and needs no global shortcut.
    public static let copyCodeBlock = EditorTool(
        id: "copycode", label: "Copy code block", symbol: "⧉", hint: "copy",
        group: "Code block", command: .copyCodeBlock)
}
