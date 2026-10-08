import AppKit
import SwiftUI

/// 자리를 적는 일은 여기서 하지 않는다. 창이 움직일 때마다 메모 창이 직접 적는다
/// (`NoteWindowConfigurator.Coordinator.observeMoves`). 이 손잡이는 탭이 하나일 때만 있어서, 여기에
/// 맡기면 탭이 둘 이상인 메모의 자리가 적히지 않는다.
struct WindowMoveHandle: NSViewRepresentable {
    let onDragCompleted: () -> Void

    func makeNSView(context: Context) -> NativeWindowDragView {
        let view = NativeWindowDragView()
        view.onDragCompleted = onDragCompleted
        return view
    }

    func updateNSView(_ nsView: NativeWindowDragView, context: Context) {
        nsView.onDragCompleted = onDragCompleted
    }
}

final class NativeWindowDragView: NSView {
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

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
