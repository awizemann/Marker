import AppKit
import SwiftUI
import Marker

/// The caret-anchored wiki-link completion popup: a borderless, NON-ACTIVATING panel attached to the
/// editor's window as a child, listing the consumer's candidates for the partial `[[query`. The text
/// view keeps key status the whole time — the coordinator's `doCommandBy` drives selection
/// (Down/Up), acceptance (Return/Tab), and dismissal (Esc) WHILE the panel is visible; clicking a
/// row accepts it directly (the panel never steals focus, so the caret never blinks away).
///
/// Owned lazily by the coordinator — a consumer that passes no `wikiCompletions` never allocates
/// one (TrapperKeeper unchanged).
@MainActor
final class WikiCompletionController {

    /// The live completion session (from `EditorCommands.wikiCompletionContext`) the visible list
    /// is for; nil while hidden.
    private(set) var context: (query: String, replaceRange: NSRange)?
    private(set) var candidates: [String] = []
    private(set) var selectedIndex = 0
    /// Accept callback: (chosen target, the query range it replaces). Set by the coordinator.
    var onAccept: ((String, NSRange) -> Void)?

    private var panel: NSPanel?
    private var hosting: NSHostingView<WikiCompletionList>?
    private var scrollObserver: NSObjectProtocol?
    /// The `[[` opener location the user Esc-dismissed at: the popup stays away while the SAME
    /// opener is live, and re-arms as soon as the caret leaves it (or a new `[[` starts).
    private var dismissedOpener: Int?

    var isVisible: Bool { panel?.isVisible ?? false }

    // NO deinit teardown: `isolated deinit` (the only way a @MainActor class can call `hide()` from
    // its deinit) requires the macOS 15.4+ runtime, above the package floor. The panel is a retained
    // CHILD WINDOW while showing (`addChildWindow` retains it), so teardown is EXPLICIT instead:
    // `EditorView.dismantleNSView` → `Coordinator.teardown()` → `hide()` detaches it when SwiftUI
    // removes the editor; `textDidEndEditing` already hides it on any focus loss before that.

    /// Recompute the session for the current text/caret and show, refresh, or hide accordingly.
    /// Called on every text change AND caret move — the trigger dies the moment the caret leaves
    /// the unclosed `[[` (the helper returns nil and we hide).
    func refresh(textView: NSTextView, model: EditorModel, theme: MarkerTheme,
                 completions: (String) -> [String]) {
        guard let ctx = EditorCommands.wikiCompletionContext(in: model.text, selection: model.selection,
                                                             document: model.document) else {
            dismissedOpener = nil   // the session ended — re-arm for the next [[
            hide()
            return
        }
        let opener = ctx.replaceRange.location - 2
        if let dismissedOpener, dismissedOpener == opener { return }   // user Esc'd THIS opener — stay away
        dismissedOpener = nil

        let items = completions(ctx.query)
        guard !items.isEmpty else { hide(); return }
        if items != candidates { selectedIndex = 0 }
        candidates = items
        selectedIndex = min(selectedIndex, items.count - 1)
        context = ctx
        show(anchoredTo: textView, theme: theme)
    }

    // MARK: Keyboard driving (coordinator's doCommandBy, only while visible)

    func moveSelection(by delta: Int) {
        guard !candidates.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + candidates.count) % candidates.count
        render(theme: nil)
    }

    /// Accept the highlighted row (Return/Tab, or a row click via `accept(index:)`).
    func acceptSelected() {
        accept(index: selectedIndex)
    }

    func accept(index: Int) {
        guard let context, candidates.indices.contains(index) else { return }
        let target = candidates[index]
        hide()
        onAccept?(target, context.replaceRange)
    }

    /// Esc: hide AND suppress re-showing for this same `[[` (typing on re-queries a fresh session).
    func dismissByUser() {
        if let context { dismissedOpener = context.replaceRange.location - 2 }
        hide()
    }

    func hide() {
        context = nil
        candidates = []
        selectedIndex = 0
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver); self.scrollObserver = nil }
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    // MARK: Panel

    private func show(anchoredTo textView: NSTextView, theme: MarkerTheme) {
        guard let window = textView.window else { hide(); return }
        let panel = ensurePanel()
        render(theme: theme)
        // Anchor just under the caret. `firstRect` is SCREEN coordinates already (bottom-left
        // origin); its origin is the caret's lower-left — exactly where the popup's top-left goes.
        let caretRect = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil)
        guard caretRect != .zero, caretRect.origin.x.isFinite, caretRect.origin.y.isFinite else { hide(); return }
        var top = NSPoint(x: caretRect.minX, y: caretRect.minY - 3)
        // Keep the popup on the caret's screen (clamp horizontally; flip above the caret when the
        // list would fall off the bottom).
        if let screen = window.screen {
            let size = panel.frame.size
            top.x = min(max(top.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - size.width)
            if top.y - size.height < screen.visibleFrame.minY { top.y = caretRect.maxY + 3 + size.height }
        }
        panel.setFrameTopLeftPoint(top)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
        // A scroll moves the text out from under the anchored panel — dismiss rather than drift.
        if scrollObserver == nil, let scrollView = textView.enclosingScrollView {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification, object: scrollView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        // `.nonactivatingPanel`: a row click must not steal key status from the text view — the
        // caret keeps blinking and typing keeps landing in the document.
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        self.panel = panel
        return panel
    }

    /// (Re)build the SwiftUI row list and size the panel to fit. `theme: nil` keeps the last theme
    /// (selection moves re-render without the caller re-plumbing it).
    private var lastTheme: MarkerTheme?
    private func render(theme: MarkerTheme?) {
        if let theme { lastTheme = theme }
        guard let theme = lastTheme, let panel else { return }
        let list = WikiCompletionList(candidates: candidates, selectedIndex: selectedIndex, theme: theme,
                                      onPick: { [weak self] index in self?.accept(index: index) })
        if let hosting {
            hosting.rootView = list
        } else {
            let hosting = NSHostingView(rootView: list)
            self.hosting = hosting
            panel.contentView = hosting
        }
        if let hosting {
            let size = hosting.fittingSize
            let origin = panel.frame.origin
            let topY = panel.frame.maxY
            panel.setFrame(NSRect(x: origin.x, y: topY - size.height, width: size.width, height: size.height),
                           display: true)
            hosting.frame = NSRect(origin: .zero, size: size)
        }
    }
}

/// The suggestion rows: highlighted current row, click to accept. Deliberately plain — a compact
/// menu, not a browser (the consumer already ranked and capped the candidates).
struct WikiCompletionList: View {
    let candidates: [String]
    let selectedIndex: Int
    let theme: MarkerTheme
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, item in
                row(index: index, item: item)
            }
        }
        .padding(4)
        .frame(width: 260, alignment: .leading)
        .background(theme.sheet, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line))
    }

    private func row(index: Int, item: String) -> some View {
        let selected = index == selectedIndex
        let rowFont: Font = theme.uiFont(12.5, selected ? .semibold : .regular)
        let rowInk: Color = selected ? theme.sheet : theme.ink
        let rowBackground: Color = selected ? theme.primary : .clear
        return Button { onPick(index) } label: {
            HStack(spacing: 6) {
                Text(item).font(rowFont).foregroundStyle(rowInk).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Link to \(item)")
    }
}
