import AppKit

/// Dev-only scroll-jump tracer (t-6cfaf799). Launch the app with `TK_SCROLL_TRACE=1` in the
/// environment and every editor clip-view origin move and text-view frame-height change is logged to
/// stderr WITH the call stack that caused it, alongside pipeline markers (selection moves, restyles,
/// table flips, full applies). Off (and zero-cost) unless the env var is set.
///
/// Why it exists: the residual long-doc click jump could not be reproduced in a headless harness —
/// every in-view path (caret move, typing, hover, table flip) held the scroll. If the jump still
/// happens in the real app, the trigger is app-environment-only (IME/accessibility/etc.); one traced
/// repro names it. Read with:  TK_SCROLL_TRACE=1 ./TrapperKeeper.app/Contents/MacOS/TrapperKeeper 2>trace.log
@MainActor
enum EditorScrollTrace {

    static let isEnabled = ProcessInfo.processInfo.environment["TK_SCROLL_TRACE"] != nil

    private static var lastClipY: CGFloat = .nan
    private static var lastHeight: CGFloat = .nan
    private static let started = Date()

    /// Wire the editor's scroll view up for tracing. No-op unless TK_SCROLL_TRACE is set.
    static func install(scrollView: NSScrollView) {
        guard isEnabled, let textView = scrollView.documentView as? NSTextView else { return }
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        textView.postsFrameChangedNotifications = true
        lastClipY = clip.bounds.origin.y
        lastHeight = textView.frame.height
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                               object: clip, queue: nil) { [weak clip] _ in
            MainActor.assumeIsolated {
                guard let clip else { return }
                let y = clip.bounds.origin.y
                if abs(y - lastClipY) > 0.5 {
                    emit(String(format: "CLIP ORIGIN %.1f -> %.1f (Δ %.1f)", lastClipY, y, y - lastClipY), stack: true)
                }
                lastClipY = y
            }
        }
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                               object: textView, queue: nil) { [weak textView] _ in
            MainActor.assumeIsolated {
                guard let textView else { return }
                let h = textView.frame.height
                if abs(h - lastHeight) > 0.5 {
                    emit(String(format: "TEXTVIEW HEIGHT %.1f -> %.1f (Δ %.1f)", lastHeight, h, h - lastHeight), stack: true)
                }
                lastHeight = h
            }
        }
        emit("installed (clip.y=\(lastClipY), height=\(lastHeight))", stack: false)
    }

    /// Drop a pipeline marker into the trace (which handler is running when the scroll moves).
    static func mark(_ label: @autoclosure () -> String) {
        guard isEnabled else { return }
        emit(label(), stack: false)
    }

    private static func emit(_ message: String, stack: Bool) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        var out = String(format: "[TKScrollTrace %8dms] %@\n", ms, message)
        if stack {
            out += Thread.callStackSymbols.dropFirst(3).prefix(18)
                .map { "    \($0)" }
                .joined(separator: "\n") + "\n"
        }
        FileHandle.standardError.write(Data(out.utf8))
    }
}
