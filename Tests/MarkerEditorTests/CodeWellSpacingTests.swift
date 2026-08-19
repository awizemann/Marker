import Testing
import AppKit
@testable import Marker
@testable import MarkerEditor

/// The fenced code block's "well" must breathe: outer air ABOVE the first line and BELOW the last so
/// the box stops crowding the prose either side, and NO extra spacing between the inner code lines
/// (which would balloon the block). The drawing side (`CodeWellGeometry`) measures the box off the
/// glyph LINE FRAGMENTS instead, so this air stays outside the box — the two must stay in lockstep.
@MainActor
@Suite("Code well spacing")
struct CodeWellSpacingTests {

    private let text = "para\n\n```swift\nlet a = 1\nlet b = 2\n```\n\nafter\n"

    /// Paragraph styles for each LINE of the document's single code block, in order.
    private func codeBlockLineStyles() throws -> [NSParagraphStyle] {
        let model = EditorModel(text: text)
        let storage = NSTextStorage(string: text)
        EditorStyler(theme: MarkerTheme.fallback).apply(to: storage, model: model)

        let block = try #require(model.document.blocks.first { if case .codeBlock = $0.kind { return true } else { return false } })
        let ns = text as NSString
        var styles: [NSParagraphStyle] = []
        var offset = block.range.location
        while offset < NSMaxRange(block.range) {
            let line = ns.lineRange(for: NSRange(location: offset, length: 0))
            let style = storage.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle
            styles.append(style ?? NSParagraphStyle.default)
            offset = NSMaxRange(line)
            if line.length == 0 { break }
        }
        return styles
    }

    @Test("the block's FIRST line carries the leading air, and only it")
    func firstLineSpacingBefore() throws {
        let styles = try codeBlockLineStyles()
        #expect(styles.count == 4)   // ```swift / let a / let b / ```
        #expect(styles[0].paragraphSpacingBefore == CodeWellMetrics.spacingBefore)
        for style in styles.dropFirst() { #expect(style.paragraphSpacingBefore == 0) }
    }

    @Test("the block's LAST line carries the trailing air, and only it")
    func lastLineSpacingAfter() throws {
        let styles = try codeBlockLineStyles()
        #expect(styles[styles.count - 1].paragraphSpacing == CodeWellMetrics.spacingAfter)
        for style in styles.dropLast() { #expect(style.paragraphSpacing == 0) }
    }

    @Test("inner code lines get no spacing at all")
    func innerLinesUnspaced() throws {
        let styles = try codeBlockLineStyles()
        for style in styles.dropFirst().dropLast() {
            #expect(style.paragraphSpacingBefore == 0)
            #expect(style.paragraphSpacing == 0)
        }
    }

    @Test("the box's interior padding never exceeds the outer air it grows into")
    func metricsAreConsistent() {
        // The box is the glyph lines grown by `interiorPadding` on each side, and that growth eats
        // into the outer air the spacing just made — a padding larger than the spacing would push
        // the box back over the prose either side (see CodeWellGeometryTests.gapsToSurroundingProse).
        #expect(CodeWellMetrics.interiorPadding <= CodeWellMetrics.spacingBefore)
        #expect(CodeWellMetrics.interiorPadding <= CodeWellMetrics.spacingAfter)
    }
}
