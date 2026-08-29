import AppKit
import SwiftUI

/// A window of its own rather than a scene: it has to come up centred and above the memos from
/// wherever it is opened — the popover or Command-comma — and the app has no main window to
/// hang a sheet on.
///
/// Deliberately not `NSApp.runModal`. A modal session swallows `terminate`, so Command-Q and the
/// popover's Quit did nothing at all while Settings was open. Nothing here needs app-modality:
/// there is no OK/Cancel, every change applies as it is made, and watching the memos change
/// underneath is the point of the language row.
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
        // Memos sit at `.floating` whenever notes are kept in front. Settings has to share that
        // level or the window the user just opened disappears behind them.
        window.level = .floating
        window.center()
        Self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func dismiss() {
        window?.close()
    }

    /// The window is not released on close, so the next `present` has to build a fresh one.
    fileprivate static func forget() {
        window = nil
    }
}

private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { SettingsModal.forget() }
    }
}
