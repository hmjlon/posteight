import AppKit
import SwiftUI

/// Locates the native editor inside this TextEditor's subtree without replacing its IME/undo behavior.
struct SearchTextEditorFocus: NSViewRepresentable {
    let request: SearchFocusRequest?
    let onApplied: ((UUID) -> Void)?

    func makeNSView(context: Context) -> Anchor {
        Anchor()
    }

    func updateNSView(_ view: Anchor, context: Context) {
        view.request = request
        view.onApplied = onApplied
        view.scheduleFocus()
    }

    final class Anchor: NSView {
        var request: SearchFocusRequest?
        var onApplied: ((UUID) -> Void)?
        private var appliedID: UUID?
        private var work: Task<Void, Never>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleFocus()
        }

        func scheduleFocus() {
            work?.cancel()
            guard request != nil, window != nil else { return }
            work = Task { @MainActor [weak self] in
                // SwiftUI installs and focuses the popover's editor after attaching the anchor.
                for _ in 0..<20 {
                    do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
                    guard let self, let request = self.request,
                          request.id != self.appliedID, !AppLock.shared.isLocked,
                          let window = self.window else { return }
                    var ancestor = self.superview
                    while let root = ancestor {
                        if let editor = self.findEditor(in: root),
                           let range = request.caret(in: editor.string),
                           window.makeFirstResponder(editor) {
                            editor.setSelectedRange(range)
                            editor.scrollRangeToVisible(range)
                            self.appliedID = request.id
                            self.onApplied?(request.id)
                            return
                        }
                        ancestor = root.superview
                    }
                }
            }
        }

        private func findEditor(in view: NSView) -> NSTextView? {
            if let editor = view as? NSTextView, editor.isEditable { return editor }
            return view.subviews.lazy.compactMap { self.findEditor(in: $0) }.first
        }
    }
}
