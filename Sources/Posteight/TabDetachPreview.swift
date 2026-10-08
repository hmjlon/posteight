import AppKit
import SwiftUI

/// A noninteractive tab that can follow the pointer beyond the source window's bounds.
@MainActor
final class TabDetachPreview {
    private var panel: NSPanel?

    func update<Content: View>(at point: NSPoint, grabOffset: CGPoint, size: CGSize,
                               sharingType: NSWindow.SharingType, @ViewBuilder content: () -> Content) {
        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: content())
            self.panel = panel
        }
        panel.sharingType = sharingType
        panel.setFrame(NSRect(x: point.x - grabOffset.x, y: point.y + grabOffset.y - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
