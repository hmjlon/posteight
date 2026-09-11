import Combine
import Foundation
import UserNotifications

/// Only the running app connects this service; isolated stores in tests never touch system alerts.
@MainActor
final class ReminderService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()
    @Published var errorMessage: String?
    private var subscription: AnyCancellable?
    private var synchronization: Task<String?, Never>?
    private let injectedClient: (any ReminderNotificationClient)?
    private lazy var systemClient: SystemReminderNotificationClient? = {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return SystemReminderNotificationClient()
    }()
    private var client: (any ReminderNotificationClient)? { injectedClient ?? systemClient }

    init(client: (any ReminderNotificationClient)? = nil) {
        injectedClient = client
        super.init()
    }

    struct Reminder: Equatable {
        let id: UUID
        let title: String
        let date: Date
    }

    nonisolated static func reminders(in notes: [StickyNote], now: Date = Date()) -> [Reminder] {
        notes.flatMap(\.allItems).compactMap { item in
            guard !item.isDone, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let date = item.reminderAt, date > now else { return nil }
            return Reminder(id: item.id, title: item.title, date: date)
        }
    }

    func connect(to store: PosteightStore) {
        guard subscription == nil, client != nil else { return }
        if injectedClient == nil { systemClient?.center.delegate = self }
        subscription = store.$notes
            .map { Self.reminders(in: $0, now: .distantPast) }
            .removeDuplicates()
            .sink { [weak self] reminders in
                self?.enqueue(reminders)
            }
    }

    @discardableResult
    private func enqueue(_ reminders: [Reminder]) -> Task<String?, Never> {
        let previous = synchronization
        let task = Task {
            _ = await previous?.value
            return await synchronize(reminders)
        }
        synchronization = task
        return task
    }

    func authorize() async throws {
        guard let client else { throw ReminderFailure.unavailable }
        let status = await client.authorizationStatus()
        switch status {
        case .authorized, .provisional:
            return
        case .denied:
            throw ReminderFailure.permissionDenied
        case .notDetermined:
            do {
                guard try await client.requestAuthorization() else { throw ReminderFailure.permissionDenied }
            } catch {
                // macOS can throw as well as return false when the permission alert is declined.
                if await client.authorizationStatus() == .denied { throw ReminderFailure.permissionDenied }
                throw error
            }
        @unknown default:
            throw ReminderFailure.unavailable
        }
    }

    /// A notification body outlives the banner: macOS draws it on the lock screen under the
    /// default preview policy and keeps it in the notification database. Pure and parameterised
    /// so both branches are testable without reaching for the settings singleton.
    nonisolated static func notificationBody(
        for reminder: Reminder, showsPreview: Bool, language: AppLanguage = .korean
    ) -> String {
        showsPreview ? reminder.title : L("예약해 둔 할 일이 있어요", language: language)
    }

    /// The picker edits minutes. Never carry its invisible seconds into the actual trigger.
    nonisolated static func minuteDate(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: floor(date.timeIntervalSinceReferenceDate / 60) * 60)
    }

    func saveReminder(store: PosteightStore, noteID: UUID, tabID: UUID, itemID: UUID, date: Date) async throws -> Date {
        let date = Self.minuteDate(date)
        guard date > Date() else { throw ReminderFailure.invalidDate }
        try await authorize()
        guard date > Date() else { throw ReminderFailure.invalidDate }
        guard let item = store.notes.first(where: { $0.id == noteID })?.tabs.first(where: { $0.id == tabID })?
            .items.first(where: { $0.id == itemID }), !item.isDone,
              !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReminderFailure.itemUnavailable }
        let previousDate = item.reminderAt
        store.setReminder(noteID: noteID, tabID: tabID, itemID: itemID, date: date)
        if await retrySynchronization(for: store.notes) != nil {
            if store.notes.flatMap(\.allItems).first(where: { $0.id == itemID })?.reminderAt == date {
                store.setReminder(noteID: noteID, tabID: tabID, itemID: itemID, date: previousDate)
                _ = await retrySynchronization(for: store.notes)
            }
            throw ReminderFailure.schedulingFailed
        }
        guard let current = store.notes.flatMap(\.allItems).first(where: { $0.id == itemID }),
              !current.isDone, current.reminderAt == date else { throw ReminderFailure.itemUnavailable }
        return date
    }

    func retrySynchronization(for notes: [StickyNote]) async -> String? {
        await enqueue(Self.reminders(in: notes)).value
    }

    private func synchronize(_ scheduled: [Reminder]) async -> String? {
        guard let client else { return ReminderFailure.unavailable.messageKey }
        errorMessage = nil
        let reminders = scheduled.filter { $0.date > Date() }
        let desiredIDs = Set(reminders.map { $0.id.uuidString })
        let pending = await client.pendingRequests()
        client.removePendingRequests(withIdentifiers: pending.map(\.identifier).filter { !desiredIDs.contains($0) })
        if !reminders.isEmpty {
            let status = await client.authorizationStatus()
            guard status == .authorized || status == .provisional else {
                errorMessage = ReminderFailure.permissionDenied.messageKey
                return errorMessage
            }
        }
        let settings = AppSettings.shared
        for reminder in reminders {
            let desiredBody = Self.notificationBody(
                for: reminder, showsPreview: settings.showsReminderPreview, language: settings.language
            )
            // Do not reset unchanged requests on every keystroke elsewhere in the app. The
            // comparison has to use the body actually about to be sent, or flipping the preview
            // setting would leave every already-scheduled notification showing the old one.
            if let request = pending.first(where: { $0.identifier == reminder.id.uuidString }),
               request.content.body == desiredBody,
               let trigger = request.trigger as? UNCalendarNotificationTrigger,
               let date = trigger.nextTriggerDate(), abs(date.timeIntervalSince(reminder.date)) < 1 { continue }
            guard reminder.date > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Posteight"
            content.body = desiredBody
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
            do {
                try await client.add(UNNotificationRequest(
                    identifier: reminder.id.uuidString, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                ))
            } catch {
                errorMessage = ReminderFailure.schedulingFailed.messageKey
            }
        }
        return errorMessage
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}


enum ReminderFailure: Error {
    case permissionDenied, unavailable, invalidDate, itemUnavailable, schedulingFailed

    var messageKey: String {
        switch self {
        case .permissionDenied: "알림을 받으려면 한 번만 허용해 주세요. 아래 버튼에서 Posteight 알림을 켤 수 있어요."
        case .unavailable: "알림은 설치된 Posteight 앱에서 사용할 수 있어요."
        case .invalidDate: "현재보다 나중 시간을 선택해 주세요."
        case .itemUnavailable: "할 일이 완료되거나 삭제되어 예약하지 못했어요."
        case .schedulingFailed: "알림을 등록하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}

@MainActor
protocol ReminderNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

@MainActor
private final class SystemReminderNotificationClient: ReminderNotificationClient {
    let center = UNUserNotificationCenter.current()
    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pendingRequests() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePendingRequests(withIdentifiers identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
}
