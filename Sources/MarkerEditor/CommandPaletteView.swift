import SwiftUI
import Marker

/// The command palette: tools where the cursor is. A glass panel anchored at the caret
/// (`driver.commandCaret`, window top-left space). With a bare caret it inserts/formats; with a
/// selection it flips to wrap / turn-into / operate-on-lines. Type to filter, ↑↓ to move, ⏎ to
/// apply, Esc (or a scrim click) to close; every tool runs through the driver (which executes an
/// `EditorCommand` via the undo-registered mutator seam).
///
/// Extracted from TrapperKeeper's CommandKView (0.6.0), themed via `MarkerTheme`. The CONSUMER
/// owns the trigger key and the presentation: overlay this view over the editor's window/pane
/// while its driver says so — e.g. `if palette.isPresented { CommandPaletteView(driver:theme:) }`
/// with a `CommandPaletteModel`, or any store conforming to `CommandPaletteDriving`. The view
/// converts the driver's window-space caret into its own overlay space, so it works overlaid on a
/// full window (TrapperKeeper) or a sub-pane (ShabuBox's notes editor) alike.
public struct CommandPaletteView<Driver: CommandPaletteDriving>: View {
    private let driver: Driver
    private let theme: MarkerTheme
    @FocusState private var searchFocused: Bool

    public init(driver: Driver, theme: MarkerTheme) {
        self.driver = driver
        self.theme = theme
    }

    /// Tools grouped by section, preserving first-appearance order (so groups render top-to-bottom).
    private var grouped: [EditorToolGroup] { EditorTool.grouped(driver.visibleTools) }

    private let paletteWidth: CGFloat = 344
    private let estimatedHeight: CGFloat = 440   // header + results + footer, for on-screen clamping

    public var body: some View {
        GeometryReader { geo in
            // The driver anchors at the caret in WINDOW space; this overlay may not start at the
            // window origin (a sub-pane host), so shift into local space before clamping.
            let origin = geo.frame(in: .global).origin
            let caret = CGPoint(x: driver.commandCaret.x - origin.x,
                                y: driver.commandCaret.y - origin.y)
            ZStack(alignment: .topLeading) {
                theme.ink.opacity(0.10)
                    .ignoresSafeArea()
                    .onTapGesture { driver.closeCommandPalette() }
                palette
                    .frame(width: paletteWidth)
                    .offset(x: anchorX(caret, in: geo.size), y: anchorY(caret, in: geo.size))
            }
        }
    }

    /// Anchor the palette's TOP-LEFT just below-right of the caret, clamped so it stays fully
    /// on-screen (flips above the caret when near the bottom edge).
    private func anchorX(_ caret: CGPoint, in size: CGSize) -> CGFloat {
        min(max(caret.x, 12), max(12, size.width - paletteWidth - 12))
    }
    private func anchorY(_ caret: CGPoint, in size: CGSize) -> CGFloat {
        min(max(caret.y + 6, 12), max(12, size.height - estimatedHeight))
    }

    private var query: Binding<String> {
        Binding(get: { driver.commandQuery }, set: { driver.commandQuery = $0 })
    }

    private var palette: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(driver.commandSelectionActive ? "✎" : "⌘").foregroundStyle(theme.primary)
                TextField(driver.commandSelectionActive ? "Do something to the selection…" : "Insert or format…",
                          text: query)
                    .textFieldStyle(.plain).font(theme.uiFont(13)).focused($searchFocused)
                    .onSubmit { driver.applyHighlightedTool() }
                Text(driver.commandSelectionActive ? "selection" : "cursor")
                    .font(theme.monoFont(9.5)).foregroundStyle(theme.primary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(tint))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Divider().overlay(theme.line)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if driver.visibleTools.isEmpty {
                        Text("No tool matches that.")
                            .font(theme.uiFont(13)).foregroundStyle(theme.faint)
                            .padding(.horizontal, 9).padding(.vertical, 12)
                    } else {
                        ForEach(grouped) { section in
                            if driver.commandQuery.isEmpty {
                                Text(section.group.uppercased()).font(theme.uiFont(10, .semibold)).tracking(0.7)
                                    .foregroundStyle(theme.faint)
                                    .padding(.horizontal, 9).padding(.top, 9).padding(.bottom, 4)
                            }
                            ForEach(section.items) { tool in
                                row(tool)
                            }
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 320)

            Divider().overlay(theme.line)
            HStack(spacing: 14) {
                hint("↑↓", "move"); hint("⏎", "apply"); hint("esc", "close")
                Spacer()
                Text(driver.commandSelectionActive ? "acting on your selection" : "inserting at the cursor")
                    .font(theme.uiFont(11)).foregroundStyle(theme.primary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .background(theme.sheet.opacity(0.82))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: theme.ink.opacity(0.45), radius: 30, x: 0, y: 26)
        .onAppear { searchFocused = true }
        .onKeyPress(.downArrow) { driver.moveCommandSelection(1); return .handled }
        .onKeyPress(.upArrow)   { driver.moveCommandSelection(-1); return .handled }
        .onKeyPress(.return)    { driver.applyHighlightedTool(); return .handled }
        .onKeyPress(.escape)    { driver.closeCommandPalette(); return .handled }
    }

    /// The active-row / icon-chip wash — the theme's accent at a whisper (mirrors the source
    /// design system's `tint`, which is its primary at 0.12).
    private var tint: Color { theme.primary.opacity(0.12) }

    private func row(_ tool: EditorTool) -> some View {
        let isActive = driver.visibleTools.firstIndex(of: tool) == driver.commandIndex
        return Button { driver.applyTool(tool) } label: {
            HStack(spacing: 11) {
                Text(tool.symbol).font(theme.monoFont(11, .semibold)).foregroundStyle(theme.deep)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tint))
                Text(tool.label).font(theme.uiFont(13)).foregroundStyle(theme.inkSoft)
                Spacer()
                if !tool.hint.isEmpty {
                    Text(tool.hint).font(theme.monoFont(10.5)).foregroundStyle(theme.faint)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 11).fill(isActive ? tint : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) { keycap(key); Text(label).font(theme.uiFont(11)) }
            .foregroundStyle(theme.faint)
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(theme.monoFont(10.5, .medium))
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(theme.ink.opacity(0.06)))
    }
}
