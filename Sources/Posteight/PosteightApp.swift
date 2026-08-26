import AppKit
import SwiftUI

enum WindowID {
    static let dailyLog = "posteight.daily-log"
    static let trash = "posteight.trash"
}

/// `WindowGroup` creates a new window on every `openWindow` call, even when the value is the
/// same. Keep note presentation idempotent because SwiftUI can evaluate more than one menu bar
/// label while rebuilding the status item.
@MainActor
final class NoteWindowCoordinator {
    static let shared = NoteWindowCoordinator()

    private final class WeakWindow {
        weak var value: NSWindow?

        init(_ value: NSWindow) {
            self.value = value
        }
    }

    private var windows: [UUID: WeakWindow] = [:]
    private var pendingNoteIDs: Set<UUID> = []

    private init() {}

    func present(_ noteID: UUID, openWindow: (UUID) -> Void) {
        if let window = windows[noteID]?.value {
            window.makeKeyAndOrderFront(nil)
            return
        }

        windows[noteID] = nil
        guard pendingNoteIDs.insert(noteID).inserted else { return }
        openWindow(noteID)
    }

    func register(_ window: NSWindow, for noteID: UUID) {
        pendingNoteIDs.remove(noteID)

        if let existingWindow = windows[noteID]?.value, existingWindow !== window {
            window.close()
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        windows[noteID] = WeakWindow(window)
    }

    func remove(_ noteID: UUID) {
        pendingNoteIDs.remove(noteID)
        windows[noteID] = nil
    }
}

@main
struct PosteightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PosteightStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Posteight", for: UUID.self) { $noteID in
            if let noteID {
                StickyNoteWindowView(noteID: noteID)
                    .environmentObject(store)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: DesignTokens.defaultNoteSize.width,
            height: DesignTokens.defaultNoteSize.height
        )
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sticky Note") {
                    store.addNote()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandGroup(replacing: .appSettings) {
                Button("설정…") {
                    SettingsModal.present(store: store)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Window("오늘 기록", id: WindowID.dailyLog) {
            DailyLogPreviewView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("휴지통", id: WindowID.trash) {
            TrashView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set the policy before SwiftUI installs MenuBarExtra. Changing it afterwards can
        // rebuild the scene and leave two status items alive for the same process.
        AppSettings.shared.applyActivationPolicy()
    }

    /// The app has no main window to reopen, so a Dock icon click brings the notes back instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        AppSettings.shared.requestShowAllNotes()
        return true
    }
}

/// Lives in the status item for the whole session, so it is also where note windows are
/// restored at launch and opened for notes added from anywhere in the app.
private struct MenuBarLabel: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checklist")

            if store.totalCount > 0 {
                Text(countLabel)
            }
        }
        .task {
            for note in store.notes {
                presentNote(note.id)
            }
        }
        .onChange(of: store.notes.map(\.id)) { previousIDs, currentIDs in
            for noteID in currentIDs where !previousIDs.contains(noteID) {
                presentNote(noteID)
            }
        }
        .onChange(of: settings.showAllNotesRequests) { _, _ in
            for note in store.notes {
                presentNote(note.id)
            }
        }
    }

    private func presentNote(_ noteID: UUID) {
        NoteWindowCoordinator.shared.present(noteID) { noteID in
            openWindow(value: noteID)
        }
    }

    private var countLabel: String {
        let count = settings.menuBarCountStyle == .done ? store.doneCount : store.remainingCount
        return "\(count)/\(store.totalCount)"
    }
}
