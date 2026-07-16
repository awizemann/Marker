import SwiftUI
import Marker

/// A real grid rendering of a markdown table — equal-width columns, per-column alignment, a light
/// header band, hairline row rules, and a rounded hairline frame — matching the design prototype's
/// `TableBlock`. It is DISPLAY-ONLY: it draws from the pure `MarkdownTable` model; the source bytes
/// (the raw `| … |` pipes) are never touched (see decision "rich-table-and-code-block-rendering").
///
/// Hosted inside the text flow by a TextKit 2 attachment (see `TableAttachment`); the grid fills the
/// attachment's width (`maxWidth: .infinity`) so it tracks the text container on resize.
struct TableGridView: View {
    let table: MarkdownTable
    let theme: MarkerTheme

    /// Header first, then data rows — one uniform row list so separators/zebra index consistently.
    private var rows: [[MarkdownTable.Cell]] { [table.header] + table.rows }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                row(rows[r], isHeader: r == 0, isLast: r == rows.count - 1)
            }
        }
        .background(theme.sheet)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.line, lineWidth: 1))
        .padding(.vertical, 4)
    }

    private func row(_ cells: [MarkdownTable.Cell], isHeader: Bool, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { c in
                cell(cells[c].text, column: c, isHeader: isHeader)
            }
        }
        .background(isHeader ? theme.well : Color.clear)
        .overlay(alignment: .bottom) {
            // Rules BETWEEN rows only; the outer frame closes the last row.
            if !isLast { Rectangle().fill(theme.line).frame(height: 1) }
        }
    }

    private func cell(_ text: String, column c: Int, isHeader: Bool) -> some View {
        let alignment = c < table.alignments.count ? table.alignments[c] : .left
        // A truly empty cell would collapse to zero height and break the row; a space holds the line.
        return Text(text.isEmpty ? " " : text)
            .font(isHeader ? theme.uiFont(12, .semibold) : theme.uiFont(13.5))
            .foregroundStyle(isHeader ? theme.muted : theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
            .multilineTextAlignment(textAlignment(alignment))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private func frameAlignment(_ a: MarkdownTable.Alignment) -> Alignment {
        switch a {
        case .left:   return .leading
        case .center: return .center
        case .right:  return .trailing
        }
    }

    private func textAlignment(_ a: MarkdownTable.Alignment) -> TextAlignment {
        switch a {
        case .left:   return .leading
        case .center: return .center
        case .right:  return .trailing
        }
    }
}
