import SwiftUI
import AppKit

/// An embedded terminal surface. Renders the controller's output in a
/// monospaced, read-only text view and forwards every keystroke to the
/// PTY, so interactive programs (ssh, gcloud reauth) work in-app.
struct TerminalView: NSViewRepresentable {
    @Bindable var controller: TerminalController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        let textView = KeyCapturingTextView()
        textView.isEditable = false          // output is not directly edited
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(white: 0.08, alpha: 1)
        textView.textColor = NSColor(white: 0.92, alpha: 1)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.allowsUndo = false
        textView.onKey = { [weak coordinator = context.coordinator] text in
            coordinator?.controller.send(text)
        }

        // Sizing required for the scroll view to scroll correctly.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        guard tv.string != controller.output else { return }

        // Keep following the output only if the user is already at (or
        // near) the bottom, so manual scrolling back isn't yanked away.
        let wasAtBottom = Self.isScrolledToBottom(nsView)

        tv.string = controller.output

        if wasAtBottom {
            // Defer to the next run-loop turn: with a large burst of
            // output (e.g. the SSH login banner) the layout pass hasn't
            // finished yet, so scrolling now would land short of the end.
            DispatchQueue.main.async {
                if let container = tv.textContainer {
                    tv.layoutManager?.ensureLayout(for: container)
                }
                let end = (tv.string as NSString).length
                tv.scrollRangeToVisible(NSRange(location: end, length: 0))
                // Also pin the clip view to the document bottom, which
                // is reliable even when the text view reports a stale
                // height for the last line.
                if let doc = nsView.documentView {
                    let maxY = max(0, doc.bounds.height - nsView.contentView.bounds.height)
                    nsView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
                    nsView.reflectScrolledClipView(nsView.contentView)
                }
            }
        }
    }

    private static func isScrolledToBottom(_ scroll: NSScrollView) -> Bool {
        let visible = scroll.contentView.bounds
        let documentHeight = scroll.documentView?.bounds.height ?? 0
        // Treat "within 40pt of the end" as being at the bottom, and an
        // empty/short document as always at the bottom.
        guard documentHeight > visible.height else { return true }
        return visible.maxY >= documentHeight - 40
    }

    final class Coordinator {
        let controller: TerminalController
        weak var textView: KeyCapturingTextView?
        init(controller: TerminalController) { self.controller = controller }
    }
}

/// An NSTextView that forwards typed characters to a callback instead
/// of editing its own content (the content is driven by PTY output).
final class KeyCapturingTextView: NSTextView {
    var onKey: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Map special keys; otherwise send the characters.
        switch event.keyCode {
        // Real terminals send CR for Return; the TTY line discipline
        // translates it to NL. Sending "\n" directly confuses shells.
        case 36: onKey?("\r")          // Return
        case 51: onKey?("\u{7f}")      // Delete/Backspace
        case 48: onKey?("\t")          // Tab
        case 53: onKey?("\u{1B}")      // Esc
        case 126: onKey?("\u{1B}[A")   // Up
        case 125: onKey?("\u{1B}[B")   // Down
        case 124: onKey?("\u{1B}[C")   // Right
        case 123: onKey?("\u{1B}[D")   // Left
        default:
            if let chars = event.characters, !chars.isEmpty {
                // Ctrl-C and friends.
                if event.modifierFlags.contains(.control),
                   let scalar = chars.unicodeScalars.first {
                    let ctrl = scalar.value & 0x1f
                    onKey?(String(UnicodeScalar(ctrl)!))
                } else {
                    onKey?(chars)
                }
            }
        }
    }
}
