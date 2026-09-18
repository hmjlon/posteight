import AppKit
import SwiftUI

struct WindowMoveHandle: NSViewRepresentable {
    let onDragEnded: () -> Void
    var onDragCompleted: (() -> Void)? = nil

    func makeNSView(context: Context) -> NativeWindowDragView {
        let view = NativeWindowDragView()
        view.onDragEnded = onDragEnded
        view.onDragCompleted = onDragCompleted
        return view
    }

    func updateNSView(_ nsView: NativeWindowDragView, context: Context) {
        nsView.onDragEnded = onDragEnded
        nsView.onDragCompleted = onDragCompleted
    }
}

final class NativeWindowDragView: NSView {
    var onDragEnded: (() -> Void)?
    var onDragCompleted: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = window.frame.origin
        window.performDrag(with: event)
        if window.frame.origin != start { onDragCompleted?() }
    }

    override var mouseDownCanMoveWindow: Bool {
        // mouseDown performs the native drag and reports its actual completion.
        false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didMoveNotification,
            object: nil
        )

        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: window
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    @objc private func windowDidMove() {
        onDragEnded?()
    }
}
