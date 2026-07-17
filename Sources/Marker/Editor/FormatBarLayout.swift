//
//  FormatBarLayout.swift
//  Marker — the format bar's tool arrangement (0.7.0)
//
//  Pure, UI-free layout logic for `FormatBar` (MarkerEditor's persistent formatting strip): split a
//  tool catalog into the bar's inline clusters plus a trailing overflow menu. Lives in the core —
//  house style keeps grouping/ordering decisions as tested pure helpers, never inline view logic —
//  and draws from the SAME `EditorTool` catalog as the command palette (one source of truth: the
//  bar never declares its own tool list, it only arranges whatever catalog it's handed).
//

import Foundation

/// The format bar's arrangement of a tool catalog: inline clusters (rendered as glyph buttons with
/// thin separators between clusters) plus the overflow tools (a trailing "more" menu).
public nonisolated struct FormatBarLayout: Equatable, Sendable {
    /// The inline clusters, in row order. Reuses `EditorToolGroup`: `group` is the cluster's
    /// accessibility label ("Inline styles", "Headings", "Lists"), `items` its tools in bar order.
    /// Clusters whose tools are absent from the catalog are dropped entirely (never an empty gap).
    public let clusters: [EditorToolGroup]
    /// Everything else, for the trailing menu: the promoted overflow tools first (Quote, Code
    /// block, Link, Table — present-in-catalog only), then any remaining catalog tools in catalog
    /// order. Empty when the catalog holds nothing beyond the clusters.
    public let overflow: [EditorTool]

    public init(clusters: [EditorToolGroup], overflow: [EditorTool]) {
        self.clusters = clusters
        self.overflow = overflow
    }
}

public extension EditorTool {

    /// The bar's inline arrangement: (cluster label, tool ids in order). Ids reference the shared
    /// catalog — the bar carries NO tool definitions of its own.
    private nonisolated static let formatBarClusterSpec: [(label: String, ids: [String])] = [
        ("Inline styles", ["bold", "italic", "strike", "code"]),
        ("Headings",      ["h1", "h2", "h3"]),
        ("Lists",         ["ul", "ol", "task"]),
    ]

    /// The overflow tools promoted to the FRONT of the menu, in this order (when present).
    private nonisolated static let formatBarOverflowFirst = ["quote", "codeblock", "link", "table"]

    /// Arrange a tool catalog for the format bar: the cluster spec above, then everything left
    /// over in the overflow menu (promoted ids first, then catalog order). Total function over any
    /// catalog — ids missing from `tools` are skipped, empty clusters dropped, and every catalog
    /// tool appears EXACTLY once across clusters + overflow (first occurrence wins on a duplicate
    /// id), so nothing in the shared catalog is ever silently unreachable from the bar.
    nonisolated static func formatBarLayout(from tools: [EditorTool] = EditorTool.cursor) -> FormatBarLayout {
        // First occurrence per id — the lookup for cluster/promotion placement.
        var byID: [String: EditorTool] = [:]
        var catalog: [EditorTool] = []   // deduped, catalog order
        for tool in tools where byID[tool.id] == nil {
            byID[tool.id] = tool
            catalog.append(tool)
        }

        var placed = Set<String>()
        let clusters: [EditorToolGroup] = formatBarClusterSpec.compactMap { label, ids in
            let items = ids.compactMap { byID[$0] }
            guard !items.isEmpty else { return nil }
            placed.formUnion(items.map(\.id))
            return EditorToolGroup(group: label, items: items)
        }

        let promoted = formatBarOverflowFirst.compactMap { byID[$0] }.filter { !placed.contains($0.id) }
        placed.formUnion(promoted.map(\.id))
        let remaining = catalog.filter { !placed.contains($0.id) }
        return FormatBarLayout(clusters: clusters, overflow: promoted + remaining)
    }

    /// The bar button's tooltip, from tool metadata ONLY: "Label (hint)" when the tool carries a
    /// hint (a shortcut or markdown cue — "Bold (⌘B)", "Heading 1 (#)"), else just the label. The
    /// bar can't know a CONSUMER's shortcut bindings, so it never invents key hints.
    nonisolated var tooltip: String {
        hint.isEmpty ? label : "\(label) (\(hint))"
    }
}
