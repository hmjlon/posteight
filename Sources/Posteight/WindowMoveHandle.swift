import AppKit
import SwiftUI

struct WindowMoveHandle: NSViewRepresentable {
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> NativeWindowDragView {
        let view = NativeWindowDragView()
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: NativeWindowDragView, context: Context) {
        nsView.onDragEnded = onDragEnded
    }
}

final class NativeWindowDragView: NSView {
    var onDragEnded: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool {
        true
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
