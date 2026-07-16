import AppKit
import SwiftUI
import Marker

/// TextKit 2 display substitution that renders markdown `.table` blocks as a real grid WITHOUT
/// touching the source bytes (see decision "rich-table-and-code-block-rendering-constraints").
///
/// The editor's storage IS the raw markdown; a grid can't be produced by attributes (ragged pipes
/// don't reflow). So instead of styling, we SUBSTITUTE what gets laid out for a table's paragraphs —
/// an `NSTextAttachment` hosting `TableGridView` — via `NSTextContentStorageDelegate`. The backing
/// store (the file's bytes) is never modified; byte-exact round-trip is preserved by construction.
///
/// Editability: the caret's table renders as RAW pipes (styled mono by `EditorStyler`) so it can be
/// read/edited in place; every other table renders as a grid. Source mode shows every table raw.
///
/// SPIKE STATUS: the length-mismatched paragraph substitution + zero-height collapse of a table's
/// trailing lines is the TextKit-2-uncertain part — dogfood the layout/selection feel.

// MARK: - Content-storage delegate (the substitution decision)

@MainActor
final class TableContentDelegate: NSObject, NSTextContentStorageDelegate {
    weak var model: EditorModel?
    /// The design tokens the grids/placeholders render with (threaded into every attachment).
    let theme: MarkerTheme
    /// Cache one attachment per distinct table source so its hosted view is reused across the frequent
    /// whole-document restyles (each keystroke) instead of rebuilt — identity stability kills flicker.
    private var attachments: [String: TableAttachment] = [:]
    /// One attachment per distinct image, keyed by url + whether bytes are present — so a placeholder
    /// rebuilds into a picture if the bytes arrive on a later open. Reused across restyles like tables.
    private var imageAttachments: [String: ImageAttachment] = [:]

    init(model: EditorModel, theme: MarkerTheme) {
        self.model = model
        self.theme = theme
        super.init()
    }

    func textContentStorage(_ textContentStorage: NSTextContentStorage,
                            textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let model, !model.isSourceMode else { return nil }   // source mode → raw
        guard let block = model.document.block(at: range.location) else { return nil }
        // Reveal-on-active: the caret's block stays raw so it can be read/edited in place (a table/image
        // is one block, so this holds for any caret offset inside it); EditorStyler paints it. Every
        // other substitutable block renders.
        if block.id == model.activeBlockID { return nil }

        switch block.kind {
        case .table:
            guard let table = MarkdownTable.parse(block.text) else { return nil }   // malformed → raw + mono
            return range.location == block.range.location
                ? gridParagraph(for: block, table: table)     // first line carries the whole grid
                : collapsedParagraph()                          // remaining lines collapse to ~0 height
        case .paragraph:
            // A paragraph that is ONLY a block-level image → the picture (or a placeholder when the
            // bytes weren't reachable). Mixed text keeps its raw markdown (v1 renders block-level only).
            guard let span = MarkdownInline.soleImageSpan(in: block.text), let dest = span.destinationRange else { return nil }
            let ns = block.text as NSString
            return imageParagraph(rawURL: ns.substring(with: dest), alt: ns.substring(with: span.contentRange),
                                  data: model.imageData[ns.substring(with: dest)])
        default:
            return nil
        }
    }

    /// The table's first paragraph, substituted with a single attachment that draws the full grid.
    private func gridParagraph(for block: MarkdownBlock, table: MarkdownTable) -> NSTextParagraph {
        if attachments.count > 128 { attachments.removeAll() }   // crude bound; distinct tables are few
        let attachment = attachments[block.text] ?? {
            let made = TableAttachment(table: table, source: block.text, theme: theme)
            attachments[block.text] = made
            return made
        }()
        return NSTextParagraph(attributedString: NSAttributedString(attachment: attachment))
    }

    /// A block-level image's paragraph, substituted with an image attachment (or a placeholder card
    /// when the bytes weren't reachable — remote / out of the doc's sandbox scope / missing / oversized).
    private func imageParagraph(rawURL: String, alt: String, data: Data?) -> NSTextParagraph {
        if imageAttachments.count > 128 { imageAttachments.removeAll() }
        // Key on presence + alt + url so a placeholder shows the RIGHT alt (two block images can share a
        // url with different alt) and rebuilds into a picture if the bytes arrive on a later open.
        let key = "\(data != nil ? "img" : "ph")|\(alt)|\(rawURL)"
        let attachment = imageAttachments[key] ?? {
            let made = ImageAttachment(picture: data.flatMap { NSImage(data: $0) }, alt: alt, theme: theme)
            imageAttachments[key] = made
            return made
        }()
        return NSTextParagraph(attributedString: NSAttributedString(attachment: attachment))
    }

    /// A near-zero-height paragraph hiding a table's remaining raw lines — the grid drawn on the first
    /// line already spans the whole table. A zero-width space carries the collapsing line-height.
    private func collapsedParagraph() -> NSTextParagraph {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 0.01
        paragraph.maximumLineHeight = 0.01
        let attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .font: NSFont.systemFont(ofSize: 0.01),
            .foregroundColor: NSColor.clear,
        ]
        return NSTextParagraph(attributedString: NSAttributedString(string: "\u{200B}", attributes: attrs))
    }
}

// MARK: - Attachment + view provider

/// A display-only attachment carrying the parsed table + its raw source (the source doubles as the
/// measurement/reuse cache key). Never inserted into the backing store — only into substituted
/// display paragraphs — so the file's bytes are untouched.
///
/// `nonisolated` to match `NSTextAttachment`'s nonisolated overrides under the project's default-Main
/// isolation; AppKit invokes these on the main thread (see [[Swift 6.2 concurrency conventions]]).
nonisolated final class TableAttachment: NSTextAttachment {
    let table: MarkdownTable
    let source: String
    let theme: MarkerTheme

    init(table: MarkdownTable, source: String, theme: MarkerTheme) {
        self.table = table
        self.source = source
        self.theme = theme
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewProvider(for parentView: NSView?,
                               location: any NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = TableGridViewProvider(textAttachment: self,
                                             parentView: parentView,
                                             textLayoutManager: textContainer?.textLayoutManager,
                                             location: location)
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

/// Hosts `TableGridView` for a `TableAttachment`, sized to the live text-container width so it tracks
/// the editor on window resize (the grid fills the width via `maxWidth: .infinity`). `nonisolated`
/// class; the view-building bodies hop to the main actor (AppKit calls them there).
nonisolated final class TableGridViewProvider: NSTextAttachmentViewProvider {

    override func loadView() {
        guard let attachment = textAttachment as? TableAttachment else { return }
        let table = attachment.table   // Sendable payload; don't send `self`/attachment across the hop
        let theme = attachment.theme   // Sendable
        view = MainActor.assumeIsolated { NSHostingView(rootView: TableGridView(table: table, theme: theme)) }
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                   location: any NSTextLocation,
                                   textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? TableAttachment else { return .zero }
        let table = attachment.table       // Sendable
        let source = attachment.source     // Sendable
        let theme = attachment.theme       // Sendable
        let available = proposedLineFragment.width > 1 ? proposedLineFragment.width : (textContainer?.size.width ?? 600)
        let width = max(80, available)
        return MainActor.assumeIsolated {
            let height = TableGridMeasure.height(source: source, table: table, width: width, theme: theme)
            return CGRect(x: 0, y: 0, width: width, height: height)
        }
    }
}

// MARK: - Height measurement (cached — the whole-doc restyle asks repeatedly)

/// Measures the grid's height at a given width by laying out an off-screen hosting view, cached by
/// (width, source) so the per-keystroke restyle doesn't re-lay-out unchanged tables.
@MainActor
enum TableGridMeasure {
    private static var cache: [String: CGFloat] = [:]

    static func height(source: String, table: MarkdownTable, width: CGFloat, theme: MarkerTheme) -> CGFloat {
        let key = "\(Int(width.rounded()))|\(source)"
        if let cached = cache[key] { return cached }
        if cache.count > 256 { cache.removeAll() }
        let host = NSHostingView(rootView: TableGridView(table: table, theme: theme))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.widthAnchor.constraint(equalToConstant: width).isActive = true
        host.layoutSubtreeIfNeeded()
        let height = max(host.fittingSize.height, 24)
        cache[key] = height
        return height
    }
}

// MARK: - Image attachment + view provider (block-level images)

/// A display-only attachment carrying an image's bytes (nil → render a placeholder) + its alt text.
/// Never inserted into the backing store — only into substituted display paragraphs — so the file's
/// bytes are untouched. `nonisolated` to match `NSTextAttachment` under the project's default-Main
/// isolation; AppKit invokes these on the main thread.
nonisolated final class ImageAttachment: NSTextAttachment {
    /// The decoded picture (nil → render a placeholder). Decoded ONCE at construction (in the delegate,
    /// on the main thread) and reused — `attachmentBounds` runs on every layout pass, so decoding
    /// per-call would re-inflate the bytes each frame. Named `picture` to avoid `NSTextAttachment.image`
    /// (whose presence would make AppKit draw the image itself, fighting our view provider).
    let picture: NSImage?
    let alt: String
    let theme: MarkerTheme

    init(picture: NSImage?, alt: String, theme: MarkerTheme) {
        self.picture = picture
        self.alt = alt
        self.theme = theme
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewProvider(for parentView: NSView?,
                               location: any NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = ImageViewProvider(textAttachment: self,
                                         parentView: parentView,
                                         textLayoutManager: textContainer?.textLayoutManager,
                                         location: location)
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

/// Hosts the picture (an `NSImageView`) or a placeholder card for an `ImageAttachment`, sized to fit
/// the text-container width WITHOUT upscaling past the image's native size. `nonisolated`; the
/// view-building bodies hop to the main actor (AppKit calls them there).
nonisolated final class ImageViewProvider: NSTextAttachmentViewProvider {

    override func loadView() {
        guard let attachment = textAttachment as? ImageAttachment else { return }
        let picture = attachment.picture   // decoded once at construction; reused here + in attachmentBounds
        let alt = attachment.alt
        let theme = attachment.theme       // Sendable
        view = MainActor.assumeIsolated {
            if let picture {
                let imageView = NSImageView()
                imageView.image = picture
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.imageAlignment = .alignTopLeft
                return imageView
            }
            return NSHostingView(rootView: ImagePlaceholderView(alt: alt, theme: theme))
        }
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                   location: any NSTextLocation,
                                   textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? ImageAttachment else { return .zero }
        let picture = attachment.picture
        let available = proposedLineFragment.width > 1 ? proposedLineFragment.width : (textContainer?.size.width ?? 600)
        let maxWidth = max(80, available)
        return MainActor.assumeIsolated {
            if let picture, picture.size.width > 0, picture.size.height > 0 {
                let scale = min(1, maxWidth / picture.size.width)   // fit width; never upscale past native
                let width = picture.size.width * scale
                let height = min(picture.size.height * scale, 640)  // cap a very tall image
                return CGRect(x: 0, y: 0, width: width, height: height)
            }
            return CGRect(x: 0, y: 0, width: maxWidth, height: 40)  // placeholder card row
        }
    }
}

/// The gentle inline card shown when an image's bytes aren't available (remote, out of the doc's
/// sandbox scope, missing, or oversized) — a photo icon + the alt text, in the muted palette.
private struct ImagePlaceholderView: View {
    let alt: String
    let theme: MarkerTheme
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo").foregroundStyle(theme.muted)
            Text(alt.isEmpty ? "Image" : alt)
                .font(theme.uiFont(11)).foregroundStyle(theme.muted)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(markerHex: 0x142818, alpha: 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line))
    }
}
