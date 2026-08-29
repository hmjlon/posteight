import AppKit
import SwiftUI

/// A real modal dialog rather than a window scene: it has to come up centred and on top from
/// wherever it is opened — the popover or Command-comma — and the app has no main window to
/// hang a sheet on.
@MainActor
enum SettingsModal {
    private static var window: NSWindow?
    private static let windowDelegate = SettingsWindowDelegate()

    static func present(store: PosteightStore) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView(onClose: dismiss)
                .environmentObject(store)
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = L("Posteight 설정")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
        window.center()
        Self.window = window

        NSApp.activate(ignoringOtherApps: true)

        // Starting the modal session after the current click lets the popover close first.
        DispatchQueue.main.async {
            NSApp.runModal(for: window)
            window.orderOut(nil)
            Self.window = nil
        }
    }

    static func dismiss() {
        NSApp.stopModal()
    }
}

private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    /// Ending the session is what hides the window, so the close button only stops the modal.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.stopModal()
        return false
    }
}
