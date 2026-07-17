import SwiftUI
import Marker

/// The persistent formatting bar: a compact single row of glyph buttons over one `EditorModel` —
/// inline styles · headings · lists, with everything else in a trailing "more" menu. Discoverable
/// where the command palette is fast: the two share the SAME `EditorTool` catalog (the bar only
/// ARRANGES it, via the core's pure `EditorTool.formatBarLayout`), and every button executes
/// through `EditorModel.runCommand` — the undo-registered mutator seam the palette uses.
///
/// The CONSUMER opts in by placing the view (a slim row above the editor, typically) and themes it
/// with its `MarkerTheme`; pass `tools:` to arrange a different catalog slice. Buttons disable
/// while the model is read-only. Stateless v1: no active-style reflection — buttons fire commands,
/// they don't mirror the caret's current formatting. Tooltips come from tool metadata only
/// (`EditorTool.tooltip` — the bar can't know a consumer's shortcut bindings).
public struct FormatBar: View {
    private let model: EditorModel
    private let theme: MarkerTheme
    private let layout: FormatBarLayout

    public init(model: EditorModel, theme: MarkerTheme, tools: [EditorTool] = EditorTool.cursor) {
        self.model = model
        self.theme = theme
        self.layout = EditorTool.formatBarLayout(from: tools)
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(layout.clusters.enumerated()), id: \.element.id) { index, cluster in
                if index > 0 { clusterDivider }
                // A real container per cluster (not bare ForEach output) so the accessibility
                // group label lands on the CLUSTER, not on every button inside it.
                HStack(spacing: 2) {
                    ForEach(cluster.items) { tool in
                        button(tool)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(cluster.group)
            }
            Spacer(minLength: 0)
            if !layout.overflow.isEmpty {
                overflowMenu
            }
        }
        .disabled(model.isReadOnly)
        .opacity(model.isReadOnly ? 0.4 : 1)
    }

    /// One tool as a glyph button (~24pt hit target — the palette's chip size). The glyph is the
    /// catalog's `symbol` in the theme's mono face, exactly as the palette renders it, so the bar
    /// and the palette read as the same system.
    private func button(_ tool: EditorTool) -> some View {
        Button { model.runCommand(tool.command) } label: {
            Text(tool.symbol)
                .font(theme.monoFont(11, .semibold))
                .foregroundStyle(theme.deep)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.tooltip)
        .accessibilityLabel(tool.label)
    }

    /// The trailing "more" menu: the catalog's remaining tools, labeled (glyph + name).
    private var overflowMenu: some View {
        Menu {
            ForEach(layout.overflow) { tool in
                Button("\(tool.symbol)  \(tool.label)") { model.runCommand(tool.command) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.muted)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More formatting tools")
        .accessibilityLabel("More formatting tools")
    }

    /// A thin vertical rule between clusters.
    private var clusterDivider: some View {
        Rectangle()
            .fill(theme.line)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 5)
            .accessibilityHidden(true)
    }
}
