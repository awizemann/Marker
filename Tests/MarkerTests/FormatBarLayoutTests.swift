import Testing
import Foundation
@testable import Marker

/// The format bar's pure arrangement logic (`EditorTool.formatBarLayout`) — the bar draws from the
/// shared catalog and must account for EVERY tool exactly once across clusters + overflow.
@Suite("FormatBarLayout — the bar's pure tool arrangement")
struct FormatBarLayoutTests {

    @Test("the default catalog arranges into the designed clusters, in order")
    func defaultCatalogClusters() {
        let layout = EditorTool.formatBarLayout()
        #expect(layout.clusters.map(\.group) == ["Inline styles", "Headings", "Lists"])
        #expect(layout.clusters.map { $0.items.map(\.id) } == [
            ["bold", "italic", "strike", "code"],
            ["h1", "h2", "h3"],
            ["ul", "ol", "task"],
        ])
    }

    @Test("overflow leads with the promoted tools, then the remaining catalog in catalog order")
    func overflowOrder() {
        let layout = EditorTool.formatBarLayout()
        let overflowIDs = layout.overflow.map(\.id)
        #expect(Array(overflowIDs.prefix(4)) == ["quote", "codeblock", "link", "table"])
        // The rest is whatever the cursor catalog holds beyond the clusters + promotions, in
        // catalog order — computed, not hardcoded, so a catalog addition can't silently vanish.
        let placed = Set(["bold", "italic", "strike", "code", "h1", "h2", "h3", "ul", "ol", "task",
                          "quote", "codeblock", "link", "table"])
        let expectedRest = EditorTool.cursor.map(\.id).filter { !placed.contains($0) }
        #expect(Array(overflowIDs.dropFirst(4)) == expectedRest)
    }

    @Test("every catalog tool appears exactly once across clusters + overflow (nothing lost, nothing doubled)")
    func conservation() {
        let layout = EditorTool.formatBarLayout()
        let all = layout.clusters.flatMap(\.items) + layout.overflow
        #expect(all.count == EditorTool.cursor.count)
        #expect(Set(all.map(\.id)) == Set(EditorTool.cursor.map(\.id)))
    }

    @Test("cluster tools keep the catalog's definitions (same labels/commands — no duplicate tool list)")
    func toolsComeFromTheCatalog() {
        let layout = EditorTool.formatBarLayout()
        for tool in layout.clusters.flatMap(\.items) + layout.overflow {
            #expect(EditorTool.cursor.contains(tool))   // full Equatable identity, not just the id
        }
    }

    @Test("ids missing from the catalog are skipped; fully-absent clusters are dropped")
    func partialCatalog() {
        // No headings at all, and only part of the inline cluster.
        let subset = EditorTool.cursor.filter { ["bold", "code", "ul", "quote"].contains($0.id) }
        let layout = EditorTool.formatBarLayout(from: subset)
        #expect(layout.clusters.map(\.group) == ["Inline styles", "Lists"])
        #expect(layout.clusters.map { $0.items.map(\.id) } == [["bold", "code"], ["ul"]])
        #expect(layout.overflow.map(\.id) == ["quote"])
    }

    @Test("tools outside the spec land in overflow after the promotions, preserving their order")
    func unknownToolsFlowToOverflow() {
        let custom = [
            EditorTool(id: "alpha", label: "Alpha", symbol: "α", group: "X", command: .bold),
            EditorTool(id: "table", label: "Table", symbol: "▦", group: "X", command: .table),
            EditorTool(id: "beta",  label: "Beta",  symbol: "β", group: "X", command: .italic),
        ]
        let layout = EditorTool.formatBarLayout(from: custom)
        #expect(layout.clusters.isEmpty)
        // "table" is promoted ahead of the unrecognized tools; alpha/beta keep catalog order.
        #expect(layout.overflow.map(\.id) == ["table", "alpha", "beta"])
    }

    @Test("a duplicated id places once — first occurrence wins")
    func duplicateIDsCollapse() {
        let doubled = EditorTool.cursor + [
            EditorTool(id: "bold", label: "Bold again", symbol: "B", group: "X", command: .bold),
        ]
        let layout = EditorTool.formatBarLayout(from: doubled)
        let all = layout.clusters.flatMap(\.items) + layout.overflow
        #expect(all.filter { $0.id == "bold" }.count == 1)
        #expect(all.first { $0.id == "bold" }?.label == "Bold")   // the catalog's, not the duplicate
    }

    @Test("an empty catalog yields an empty bar")
    func emptyCatalog() {
        let layout = EditorTool.formatBarLayout(from: [])
        #expect(layout.clusters.isEmpty)
        #expect(layout.overflow.isEmpty)
    }

    @Test("tooltip is 'Label (hint)' from metadata, or just the label when the tool has no hint")
    func tooltips() {
        let bold = EditorTool.cursor.first { $0.id == "bold" }!
        #expect(bold.tooltip == "Bold (⌘B)")
        let h1 = EditorTool.cursor.first { $0.id == "h1" }!
        #expect(h1.tooltip == "Heading 1 (#)")
        let table = EditorTool.cursor.first { $0.id == "table" }!
        #expect(table.tooltip == "Table")   // no hint in the catalog → no parenthetical
    }
}
