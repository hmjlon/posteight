import AppKit
import SwiftUI

/// The menu bar popover: quick capture, today's task status, and access to the
/// trash window. Kept compact on purpose — notes stay the working surface.
struct MenuBarPanelView: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var lock = AppLock.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header

            Divider()
                .padding(.vertical, 4)

            if lock.isLocked {
                PanelRow(title: L("잠금 해제"), systemImage: "lock.open") {
                    AppUnlockWindow.present()
                }
                PanelRow(title: L("메모 보기"), systemImage: "rectangle.on.rectangle") {
                    showNotes(store.notes.map(\.id))
                    AppUnlockWindow.present()
                }
            } else if store.isStorageBlocked {
                StorageStatusView()
            } else {
                StorageStatusView()
                ReminderStatusView()
                PanelRow(title: L("새 메모"), systemImage: "plus", shortcut: "⌘N") {
                    showNote(store.addNote(language: settings.language,
                                           origin: NSScreen.noteSpawnOrigin))
                }

                PanelRow(title: L("메모 검색…"), systemImage: "magnifyingglass") {
                    open(windowID: WindowID.search)
                }

                PanelRow(title: L("메모 보기"), systemImage: "rectangle.on.rectangle") {
                    showNotes(store.notes.map(\.id))
                }

                PanelRow(title: L("모든 메모 숨기기"), systemImage: "eye.slash") {
                    NoteWindowCoordinator.shared.hideAll()
                }

                PanelRow(
                    title: L("휴지통"),
                    systemImage: trashIsEmpty ? "trash" : "trash.fill",
                    badge: trashIsEmpty ? nil : "\(store.trashedNotes.count + store.trashedTabs.count)"
                ) {
                    open(windowID: WindowID.trash)
                }

                Divider()
                    .padding(.vertical, 4)

                if lock.isEnabled {
                    PanelRow(title: L("Posteight 잠그기"), systemImage: "lock") {
                        for window in NSApp.windows { window.makeFirstResponder(nil) }
                        store.flush()
                        SettingsModal.dismiss()
                        lock.lock()
                    }
                }
            }

            PanelRow(title: L("설정…"), systemImage: "gearshape", shortcut: "⌘,") {
                SettingsModal.present(store: store)
            }

            PanelRow(title: L("Posteight 종료"), systemImage: "power", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 224)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Posteight")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Spacer(minLength: 0)

            Text(statusLabel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private var trashIsEmpty: Bool {
        store.trashedNotes.isEmpty && store.trashedTabs.isEmpty
    }

    private var statusLabel: String {
        guard !lock.isLocked else { return L("잠겨 있어요") }
        guard store.totalCount > 0 else {
            return L("할 일 없음")
        }

        switch settings.menuBarCountStyle {
        case .remaining, .hidden:
            return store.remainingCount > 0
                ? Lf("남은 일 %ld개", store.remainingCount)
                : L("모두 완료")
        case .done:
            return Lf("완료 %ld개", store.doneCount)
        }
    }

    private func showNote(_ noteID: UUID) {
        NoteWindowCoordinator.shared.present(noteID) { noteID in
            openWindow(value: noteID)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showNotes(_ noteIDs: [UUID]) {
        for noteID in noteIDs {
            showNote(noteID)
        }
    }

    private func open(windowID: String) {
        openWindow(id: windowID)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PanelRow: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    var badge: String?
    let action: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isHovered = false

    var body: some View {
        // Every row here opens a window or quits, so the popover has finished its job either
        // way. Closing it from this one place beats remembering to do it in six actions.
        Button {
            dismiss()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))

                Spacer(minLength: 0)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Color.primary.opacity(0.62), in: Circle())
                }

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.09) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// 예약 알림을 자동으로 맞추다 실패한 것을 알린다. 알림 권한을 나중에 끈 경우처럼 사용자가 알림 창을
/// 열지 않은 경로에서는 이것 말고 알 길이 없고, 할 일의 종은 채워진 채 아무 알림도 오지 않는다.
private struct ReminderStatusView: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var reminders = ReminderService.shared

    var body: some View {
        if let message = reminders.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label(L(message), systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.red)
                HStack(spacing: 12) {
                    // 권한을 아직 묻지 않은 Mac 이면 여기서 묻는다. 거절된 권한은 설정에서만 켤 수 있다.
                    Button(L("다시 시도")) {
                        Task {
                            try? await reminders.authorize()
                            _ = await reminders.retrySynchronization(for: store.notes)
                        }
                    }
                    if message == ReminderFailure.permissionDenied.messageKey {
                        Link(L("알림 설정 열기"),
                             destination: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
                .font(.caption)
            }
            .padding(8)
        }
    }
}
