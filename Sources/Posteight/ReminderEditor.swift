import SwiftUI

struct ReminderEditor: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var settings = AppSettings.shared
    let noteID: UUID
    let tabID: UUID
    let item: TodoItem
    let onClose: () -> Void
    @State private var date: Date
    @State private var isSaving = false
    @State private var failure: ReminderFailure?
    @State private var savedDate: Date?

    init(noteID: UUID, tabID: UUID, item: TodoItem, onClose: @escaping () -> Void) {
        self.noteID = noteID
        self.tabID = tabID
        self.item = item
        self.onClose = onClose
        _date = State(initialValue: ReminderService.minuteDate(
            item.reminderAt.flatMap { $0 > Date() ? $0 : nil } ?? Date().addingTimeInterval(3600)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("알림 예약")).font(.headline)
            Text(item.title).lineLimit(2)
            DatePicker(L("날짜와 시간"), selection: $date, displayedComponents: [.date, .hourAndMinute])
                .environment(\.locale, Locale(identifier: settings.language.resolved == .korean ? "ko_KR" : "en_US"))
                .disabled(isSaving)
            if let savedDate {
                Label(L("예약 완료"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(savedDate, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
            } else if let failure {
                Text(L(failure.messageKey)).font(.caption).foregroundStyle(.secondary)
                if failure == .permissionDenied {
                    Link(L("알림 설정 열기"), destination: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        .font(.caption)
                }
            } else {
                Text(L("처음 예약할 때 macOS 알림 허용이 필요해요."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if item.reminderAt != nil || savedDate != nil {
                    Button(L("알림 해제")) {
                        store.setReminder(noteID: noteID, tabID: tabID, itemID: item.id, date: nil)
                        onClose()
                    }
                    .disabled(isSaving)
                }
                Spacer()
                if isSaving {
                    ProgressView().controlSize(.small)
                    Text(L("예약 중…")).font(.caption)
                }
                Button(L(savedDate == nil ? "취소" : "닫기"), action: onClose)
                    .disabled(isSaving)
                if savedDate == nil {
                    Button(L("예약"), action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving)
                }
            }
        }
        .foregroundStyle(Color.black.opacity(0.8))
        .environment(\.colorScheme, .light)
        .padding(16)
        .frame(width: 340)
        // Keep the result visible when macOS opens its permission alert or System Settings.
        .interactiveDismissDisabled(true)
        .onChange(of: date) { _, _ in
            savedDate = nil
            failure = nil
        }
    }

    private func save() {
        isSaving = true
        failure = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                savedDate = try await ReminderService.shared.saveReminder(
                    store: store, noteID: noteID, tabID: tabID, itemID: item.id, date: date
                )
            } catch {
                failure = (error as? ReminderFailure) ?? .schedulingFailed
            }
        }
    }
}
