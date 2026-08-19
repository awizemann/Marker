import Testing
import AppKit
@testable import Marker
@testable import MarkerEditor

/// The DRAWN code well's vertical contract, exercised against a real TextKit 2 stack.
///
/// The box is measured from the block's text LINE FRAGMENTS, not from `layoutFragmentFrame`: TextKit 2
/// folds the styler's outer paragraph spacing into the layout fragment, but it does NOT apply
/// `paragraphSpacing` to a final paragraph with no trailing newline — so the old "subtract the spacing
/// back out" arithmetic cut the box ~10pt into the closing fence of a block at EOF, and produced an
/// oversized frame for an unterminated fence. Every case below must land the same way: the box brackets
/// the code's glyph lines with exactly `interiorPadding` of air above and below.
@MainActor
@Suite("Code well geometry")
struct CodeWellGeometryTests {

    /// A laid-out TextKit 2 stack over `text`, styled exactly as the editor styles it.
    private struct Stack {
        let storage: NSTextStorage
        let layoutManager: NSTextLayoutManager
        let model: EditorModel
    }

    private func stack(_ text: String) -> Stack {
        let model = EditorModel(text: text)
        let storage = NSTextStorage(string: text)
        EditorStyler(theme: MarkerTheme.fallback).apply(to: storage, model: model)

        let content = NSTextContentStorage()
        content.textStorage = storage
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 5
        layoutManager.textContainer = container
        content.addTextLayoutManager(layoutManager)
        // Tests own the layout: nothing is on screen, so lay the whole document out up front. The
        // drawing code itself never forces layout (it decorates what is already laid out).
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        return Stack(storage: storage, layoutManager: layoutManager, model: model)
    }

    private func codeBlockRange(_ stack: Stack) throws -> NSRange {
        let block = try #require(stack.model.document.blocks.first {
            if case .codeBlock = $0.kind { return true } else { return false }
        })
        return block.range
    }

    /// The glyph extent of `range` — typographic SEGMENTS, an independent measurement path from the
    /// line-fragment union the geometry under test uses.
    private func segmentUnion(_ stack: Stack, _ range: NSRange) throws -> CGRect {
        let textRange = try #require(CodeWellGeometry.textRange(for: range, in: stack.layoutManager))
        var union = CGRect.null
        stack.layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            union = union.union(frame)
            return true
        }
        #expect(!union.isNull)
        return union
    }

    /// Every case shares one contract: the box brackets the code glyphs by `interiorPadding`.
    private func assertBracketsGlyphs(_ text: String, _ sourceLocation: SourceLocation = #_sourceLocation) throws {
        let stack = stack(text)
        let range = try codeBlockRange(stack)
        let box = try #require(CodeWellGeometry.wellBox(for: range, in: stack.layoutManager), sourceLocation: sourceLocation)
        let glyphs = try segmentUnion(stack, range)
        let pad = CodeWellMetrics.interiorPadding
        // Tolerance covers the sub-point difference between a segment rect and its line fragment.
        #expect(abs(box.minY - (glyphs.minY - pad)) < 1, sourceLocation: sourceLocation)
        #expect(abs(box.maxY - (glyphs.maxY + pad)) < 1, sourceLocation: sourceLocation)
        // The closing fence is INSIDE the box, with real clearance — the exact thing the old
        // spacing-subtraction got wrong at EOF.
        #expect(box.maxY >= glyphs.maxY + pad - 1, sourceLocation: sourceLocation)
        #expect(box.height > 0, sourceLocation: sourceLocation)
    }

    @Test("block followed by prose, trailing newline")
    func blockFollowedByProse() throws {
        try assertBracketsGlyphs("para\n\n```swift\nlet a = 1\nlet b = 2\n```\n\nafter\n")
    }

    @Test("block at EOF with no trailing newline")
    func blockAtEndOfFile() throws {
        try assertBracketsGlyphs("para\n\n```swift\nlet a = 1\nlet b = 2\n```")
    }

    @Test("unterminated fence at EOF")
    func unterminatedFence() throws {
        try assertBracketsGlyphs("para\n\n```swift\nlet a = 1")
    }

    @Test("the box leaves the styler's outer air as a real gap to the prose either side")
    func gapsToSurroundingProse() throws {
        let text = "para\n\n```swift\nlet a = 1\n```\n\nafter\n"
        let stack = stack(text)
        let range = try codeBlockRange(stack)
        let box = try #require(CodeWellGeometry.wellBox(for: range, in: stack.layoutManager))
        let ns = text as NSString
        let before = try segmentUnion(stack, ns.range(of: "para"))
        let after = try segmentUnion(stack, ns.range(of: "after"))
        #expect(box.minY > before.maxY)   // air above the box
        #expect(box.maxY < after.minY)    // air below it
    }

    @Test("box() is a pure vertical inset of the line-fragment union")
    func boxIsAPureInset() {
        let union = CGRect(x: 3, y: 40, width: 200, height: 30)
        let box = CodeWellGeometry.box(forLineFragmentUnion: union)
        #expect(box.minY == union.minY - CodeWellMetrics.interiorPadding)
        #expect(box.maxY == union.maxY + CodeWellMetrics.interiorPadding)
        #expect(box.minX == union.minX)     // horizontal extent is the caller's business
        #expect(box.width == union.width)
    }

    @Test("a range that isn't laid out yields no box")
    func unlaidRangeIsNil() {
        let stack = stack("plain prose, no code\n")
        #expect(CodeWellGeometry.wellBox(for: NSRange(location: 900, length: 5), in: stack.layoutManager) == nil)
    }
}
