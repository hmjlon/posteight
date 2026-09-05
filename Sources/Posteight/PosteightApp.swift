import AppKit
import SwiftUI

enum WindowID {
    static let dailyLog = "posteight.daily-log"
    static let trash = "posteight.trash"
}

struct NoteWindowVisibility {
    private(set) var hiddenNoteIDs: Set<UUID> = []

    mutating func hide(_ noteID: UUID) {
        hiddenNoteIDs.insert(noteID)
    }

    mutating func hideAll(registered: Set<UUID>, pending: Set<UUID>) {
        hiddenNoteIDs.formUnion(registered)
        hiddenNoteIDs.formUnion(pending)
    }

    mutating func present(_ noteID: UUID) {
        hiddenNoteIDs.remove(noteID)
    }

    mutating func remove(_ noteID: UUID) {
        hiddenNoteIDs.remove(noteID)
    }

    func isHidden(_ noteID: UUID) -> Bool {
        hiddenNoteIDs.contains(noteID)
    }

    /// A screen lock hides windows without changing what the user chose to hide, so unlocking
    /// may only bring back the ones the lock itself took away.
    func restorableAfterLock(_ lockHidden: Set<UUID>) -> Set<UUID> {
        lockHidden.subtracting(hiddenNoteIDs)
    }
}

/// `WindowGroup` creates a new window on every `openWindow` call, even for the same value.
/// Keep presentation idempotent while still allowing every memo ID its own window.
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
    private var visibility = NoteWindowVisibility()
    private var lockHiddenNoteIDs: Set<UUID> = []

    private init() {
        observeScreenLock()
    }

    /// Locking the screen is the one moment the app can be certain the user walked away, and it
    /// costs no permission to hear about. Notes drop out of sight until the session comes back.
    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideForScreenLock() }
        }
        center.addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revealAfterScreenUnlock() }
        }
    }

    /// A miniaturized or already hidden window has nothing left to hide. Remembering exactly
    /// which windows the lock took away keeps the unlock from changing anything else.
    private func hideForScreenLock() {
        lockHiddenNoteIDs = []

        for (noteID, weakWindow) in windows {
            guard let window = weakWindow.value, window.isVisible else { continue }
            window.orderOut(nil)
            lockHiddenNoteIDs.insert(noteID)
        }
    }

    private func revealAfterScreenUnlock() {
        // `orderFront` rather than `makeKeyAndOrderFront`: coming back to a locked Mac lands in
        // whatever app was in front, and the notes have no business taking that away.
        for noteID in visibility.restorableAfterLock(lockHiddenNoteIDs) {
            windows[noteID]?.value?.orderFront(nil)
        }

        lockHiddenNoteIDs = []
    }

    func present(_ noteID: UUID, openWindow: (UUID) -> Void) {
        visibility.present(noteID)

        if let window = windows[noteID]?.value {
            // `makeKeyAndOrderFront` leaves a miniaturized window in the Dock.
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            // Showing every note has to reach the ones stranded off screen, too.
            window.moveOnScreenIfNeeded()
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
            if visibility.isHidden(noteID) {
                existingWindow.orderOut(nil)
                return
            }
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        windows[noteID] = WeakWindow(window)

        // A window requested just before Hide All can finish being created afterwards. Keep it
        // out of sight until the user explicitly presents that memo again.
        if visibility.isHidden(noteID) {
            window.orderOut(nil)
        }
    }

    func hideAll() {
        visibility.hideAll(registered: Set(windows.keys), pending: pendingNoteIDs)

        for window in windows.values.compactMap(\.value) {
            window.orderOut(nil)
        }
    }

    func hide(_ noteID: UUID) {
        visibility.hide(noteID)
        windows[noteID]?.value?.orderOut(nil)
    }

    func remove(_ noteID: UUID) {
        pendingNoteIDs.remove(noteID)
        visibility.remove(noteID)
        windows[noteID] = nil
    }
}

/// Memo contents are the whole promise of the app, so every window that shows them stays out of
/// screen shares, recordings and screenshots. One flag, no permission, nothing to configure.
struct ScreenCaptureExclusion: NSViewRepresentable {
    @ObservedObject private var settings = AppSettings.shared

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        exclude(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        exclude(nsView)
    }

    private func exclude(_ view: NSView) {
        let sharingType = settings.noteWindowSharingType
        // The view has no window yet while SwiftUI is still building the scene.
        DispatchQueue.main.async {
            view.window?.sharingType = sharingType
        }
    }
}

extension View {
    func excludedFromScreenCapture() -> some View {
        background(ScreenCaptureExclusion())
    }
}

@main
struct PosteightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PosteightStore(language: AppSettings.shared.language)

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
                Button(L("새 메모")) {
                    store.addNote(language: AppSettings.shared.language)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandGroup(replacing: .appSettings) {
                Button(L("설정…")) {
                    SettingsModal.present(store: store)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Window("오늘 기록", id: WindowID.dailyLog) {
            DailyLogPreviewView()
                .environmentObject(store)
                .excludedFromScreenCapture()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("휴지통", id: WindowID.trash) {
            TrashView()
                .environmentObject(store)
                .excludedFromScreenCapture()
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

/// Lives in the status item for the whole session, restoring each independent memo window and
/// opening newly created memos from anywhere in the app.
private struct MenuBarLabel: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Keep the brand mark intact and let the count read as status beside it. With no tasks,
        // the number disappears and the quiet icon is all the app needs to leave behind.
        MenuBarProgressCard(done: store.doneCount, total: store.totalCount, count: displayCount)
            .accessibilityLabel(accessibilityLabel)
        .task {
            for note in store.notes {
                presentNote(note.id)
            }
        }
        .onChange(of: store.notes.map(\.id)) { previousIDs, currentIDs in
            if let noteID = currentIDs.first(where: { !previousIDs.contains($0) }) {
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

    private var displayCount: Int {
        settings.menuBarCountStyle == .done ? store.doneCount : store.remainingCount
    }

    private var accessibilityLabel: String {
        guard store.totalCount > 0 else { return "Posteight" }
        if store.doneCount >= store.totalCount {
            return "Posteight, \(L("모두 완료"))"
        }

        let status = settings.menuBarCountStyle == .done
            ? Lf("완료 %ld개", store.doneCount)
            : Lf("남은 일 %ld개", store.remainingCount)
        return "Posteight, \(status)"
    }
}
