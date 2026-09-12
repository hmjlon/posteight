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
    private var historyMonitor: Any?
    private var screenMonitor: Any?

    private init() {
        observeScreenLock()
    }

    func installHistoryShortcuts(store: PosteightStore) {
        guard historyMonitor == nil else { return }
        historyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak store] event in
            guard let store, let shortcut = NoteKeyboardShortcut(event: event),
                  shortcut == .undo || shortcut == .redo else { return event }
            if let editor = (event.window ?? NSApp.keyWindow)?.firstResponder as? NSTextView {
                // Let the IME finish its own composition. Other native editors (e.g. settings)
                // keep their native history; memo fields explicitly disable it in their cell.
                if editor.hasMarkedText() { return event }
                if let field = editor.delegate as? NSTextField, field.cell?.allowsUndo == true {
                    return event
                }
            }
            let handled = shortcut == .undo ? store.undo() : store.redo()
            return handled ? nil : event
        }
    }

    /// 디스플레이가 붙거나 빠지거나, 해상도나 배치가 바뀌면 macOS 가 창을 알아서 옮긴다. 그
    /// 이동은 마우스로 끈 것이 아니라서 `onMoveEnded` 가 뜨지 않고, 저장값은 이제 없는 모니터의
    /// 좌표로 남는다. 다음 실행에 그 좌표를 복원하면 메모는 마지막으로 본 자리가 아니라
    /// `moveOnScreenIfNeeded` 가 끌어다 놓은 구석에 뜬다.
    ///
    /// 옮겨진 자리를 그 자리에서 다시 적는다. 이때 `NSScreen.noteAnchor` 도 이미 새 값이라,
    /// 주 디스플레이가 바뀌어 기준 높이가 달라진 경우까지 같이 맞춰진다.
    ///
    /// 무엇을 내주는지 분명히 해 둔다. 외장을 꽂은 채 잠들었다가 연결이 끊기면 macOS 가 창을
    /// 내장으로 몰아넣는데, 그 자리를 여기서 적어 버리므로 모니터가 돌아와도 메모는 돌아오지
    /// 않는다. 그 대신 "뽑고 나면 메모가 마지막으로 본 자리에 있다" 를 얻는다. 적지 않는 쪽을
    /// 골라도 이득이 없다 — 예전에도 다음 실행에 그 좌표는 어차피 클램프됐고, 구석은 원래
    /// 자리보다 더 낯설다.
    func observeScreenChanges(store: PosteightStore) {
        guard screenMonitor == nil else { return }
        screenMonitor = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak store] _ in
            MainActor.assumeIsolated {
                guard let store else { return }
                NoteWindowCoordinator.shared.resaveWindowPositions(into: store)
            }
        }
    }

    /// 숨긴 창도 함께 적는다. 지금 보이지 않을 뿐 다음에 `present` 가 부를 때 같은 판정을 거치고,
    /// 저장값만 옛 모니터에 남겨 두면 그때 가서 똑같이 어긋난다.
    private func resaveWindowPositions(into store: PosteightStore) {
        for (noteID, weakWindow) in windows {
            guard let window = weakWindow.value else { continue }
            window.moveOnScreenIfNeeded()
            guard let position = window.notePosition else { continue }
            store.updateNotePosition(noteID, position: position)
        }
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
            window.alphaValue = 1
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

    func dropTarget(at point: NSPoint, excluding sourceID: UUID) -> UUID? {
        for window in NSApp.orderedWindows where window.isVisible && !window.isMiniaturized && window.frame.contains(point) {
            if let entry = windows.first(where: { $0.key != sourceID && $0.value.value === window }) {
                return entry.key
            }
        }
        return nil
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

/// Lets AppKit report the moment the view lands in a window. Leaning on a single `async` hop
/// instead loses the exclusion whenever `window` is still nil at that point: optional chaining
/// swallows it, nothing logs, and it never applies again unless `updateNSView` happens to run.
final class SharingTypeView: NSView {
    var sharingType: NSWindow.SharingType = .none {
        didSet { window?.sharingType = sharingType }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.sharingType = sharingType
    }
}

/// Memo contents are the whole promise of the app, so every window that shows them stays out of
/// screen shares, recordings and screenshots. One flag, no permission, nothing to configure.
///
/// `sharingType` is per-NSWindow and is not inherited, so popovers and sheets — which get their
/// own windows — each need this too, not just the card underneath them.
struct ScreenCaptureExclusion: NSViewRepresentable {
    @ObservedObject private var settings = AppSettings.shared

    func makeNSView(context: Context) -> NSView {
        let view = SharingTypeView()
        view.sharingType = settings.noteWindowSharingType
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? SharingTypeView)?.sharingType = settings.noteWindowSharingType
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
    @ObservedObject private var reminders = ReminderService.shared

    var body: some View {
        // Keep the brand mark intact and let the count read as status beside it. With no tasks,
        // the number disappears and the quiet icon is all the app needs to leave behind.
        MenuBarProgressCard(done: store.doneCount, total: store.totalCount, count: displayCount)
            .accessibilityLabel(accessibilityLabel)
        .task {
            // 창을 하나라도 열기 전에 끝나야 한다. 아래 presentNote 가 만드는 창이 이 값을
            // 읽어 자리를 잡고, 한 번 자리를 잡은 창은 다시 잡지 않는다.
            if let anchor = NSScreen.noteAnchor {
                store.rebaseNotePositions(from: NSScreen.main?.visibleFrame ?? anchor, to: anchor)
            }
            NoteWindowCoordinator.shared.installHistoryShortcuts(store: store)
            NoteWindowCoordinator.shared.observeScreenChanges(store: store)
            reminders.connect(to: store)
            for note in store.notes {
                presentNote(note.id)
            }
        }
        .onChange(of: store.notes.map(\.id)) { previousIDs, currentIDs in
            if let noteID = currentIDs.first(where: { !previousIDs.contains($0) }) {
                presentNote(noteID)
            }
        }
        .onChange(of: store.historyWindowRequest) { _, request in
            guard let request else { return }
            if request.show {
                NoteWindowCoordinator.shared.present(request.noteID) { openWindow(value: $0) }
            } else {
                NoteWindowCoordinator.shared.hide(request.noteID)
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

    private var displayCount: Int? {
        switch settings.menuBarCountStyle {
        case .remaining: store.remainingCount
        case .done: store.doneCount
        case .hidden: nil
        }
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
