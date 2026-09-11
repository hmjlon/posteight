import Foundation
import Testing
import UserNotifications
@testable import Posteight

@MainActor
private final class FakeReminderClient: ReminderNotificationClient {
    var status: UNAuthorizationStatus = .authorized
    var declineByThrowing = false
    var failNextAdd = false
    var authorizationRequests = 0
    var requests: [String: UNNotificationRequest] = [:]
    var duringAuthorization: (() -> Void)?

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        duringAuthorization?()
        if declineByThrowing {
            status = .denied
            throw CocoaError(.userCancelled)
        }
        status = .authorized
        return true
    }
    func pendingRequests() async -> [UNNotificationRequest] { Array(requests.values) }
    func add(_ request: UNNotificationRequest) async throws {
        if failNextAdd {
            failNextAdd = false
            throw CocoaError(.fileWriteUnknown)
        }
        requests[request.identifier] = request
    }
    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for id in identifiers { requests[id] = nil }
    }
}

@Suite("Reminder scheduling", .serialized)
@MainActor
struct ReminderSchedulingTests {
    private func fixture() throws -> (URL, PosteightStore, UUID, UUID, UUID) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let tabID = try #require(store.notes.first { $0.id == noteID }?.selectedTabID)
        let itemID = try #require(store.addItem(to: noteID, tabID: tabID))
        store.updateItemTitle(noteID: noteID, tabID: tabID, itemID: itemID, title: "예약 테스트")
        return (directory, store, noteID, tabID, itemID)
    }

    @Test("Denied permission keeps the item unscheduled and does not repeat the system prompt")
    func denied() async throws {
        let (directory, store, n, t, i) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FakeReminderClient()
        client.status = .denied
        let service = ReminderService(client: client)
        await #expect(throws: ReminderFailure.permissionDenied) {
            try await service.saveReminder(store: store, noteID: n, tabID: t, itemID: i, date: Date().addingTimeInterval(600))
        }
        #expect(client.authorizationRequests == 0)
        #expect(client.requests.isEmpty)
        #expect(store.notes.flatMap(\.allItems).first { $0.id == i }?.reminderAt == nil)
    }

    @Test("macOS denial reported as an error still produces permission guidance")
    func thrownDenial() async throws {
        let (directory, store, n, t, i) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FakeReminderClient()
        client.status = .notDetermined
        client.declineByThrowing = true
        let service = ReminderService(client: client)
        await #expect(throws: ReminderFailure.permissionDenied) {
            try await service.saveReminder(store: store, noteID: n, tabID: t, itemID: i, date: Date().addingTimeInterval(600))
        }
        #expect(client.requests.isEmpty)
    }

    @Test("Successful scheduling registers a minute-exact trigger and persists the same date")
    func successful() async throws {
        let (directory, store, n, t, i) = try fixture()
        // Pinned rather than assumed: the setting lives in the real defaults, so a developer who
        // turned the preview on in the app would otherwise see this test fail on their machine.
        let previous = AppSettings.shared.showsReminderPreview
        defer {
            AppSettings.shared.showsReminderPreview = previous
            try? FileManager.default.removeItem(at: directory)
        }
        AppSettings.shared.showsReminderPreview = false
        let client = FakeReminderClient()
        client.status = .notDetermined
        let service = ReminderService(client: client)
        let chosen = Date().addingTimeInterval(600)
        let saved = try await service.saveReminder(store: store, noteID: n, tabID: t, itemID: i, date: chosen)
        let request = try #require(client.requests[i.uuidString])
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.second == 0)
        #expect(!trigger.repeats)
        #expect(request.content.body == L("예약해 둔 할 일이 있어요"))
        #expect(request.content.body != "예약 테스트")
        #expect(saved == ReminderService.minuteDate(chosen))
        let reloaded = PosteightStore(directory: directory)
        #expect(reloaded.notes.flatMap(\.allItems).first { $0.id == i }?.reminderAt == saved)
        #expect(client.authorizationRequests == 1)
    }

    @Test("A failed replacement restores the previously saved reminder")
    func failedReplacement() async throws {
        let (directory, store, n, t, i) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FakeReminderClient()
        let service = ReminderService(client: client)
        let old = try await service.saveReminder(store: store, noteID: n, tabID: t, itemID: i, date: Date().addingTimeInterval(600))
        client.failNextAdd = true
        await #expect(throws: ReminderFailure.schedulingFailed) {
            try await service.saveReminder(store: store, noteID: n, tabID: t, itemID: i, date: old.addingTimeInterval(600))
        }
        let reloaded = PosteightStore(directory: directory)
        #expect(reloaded.notes.flatMap(\.allItems).first { $0.id == i }?.reminderAt == old)
        let trigger = try #require(client.requests[i.uuidString]?.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.nextTriggerDate() == old)
    }

    @Test("Completing the item while permission is pending prevents scheduling")
    func completedDuringPermission() async throws {
        let (directory, store, n, t, i) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FakeReminderClient()
        client.status = .notDetermined
        client.duringAuthorization = { store.toggleItem(noteID: n, tabID: t, itemID: i) }
        let service = ReminderService(client: client)
        await #expect(throws: ReminderFailure.itemUnavailable) {
            try await service.saveReminder(store: store, noteID: n, tabID: t, itemID: i, date: Date().addingTimeInterval(600))
        }
        #expect(client.requests.isEmpty)
    }

    @Test("Past minutes are rejected before requesting permission")
    func pastDate() async throws {
        let (directory, store, n, t, i) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FakeReminderClient()
        let service = ReminderService(client: client)
        await #expect(throws: ReminderFailure.invalidDate) {
            try await service.saveReminder(store: store, noteID: n, tabID: t, itemID: i, date: Date())
        }
        #expect(client.authorizationRequests == 0)
    }

    /// A trigger built from bare `DateComponents` has a nil `timeZone`, and macOS reads those
    /// wall-clock fields in whichever zone the Mac is in at fire time. The moment the user picked
    /// has to survive a flight.
    @Test("A trigger keeps its absolute instant across time zones")
    func triggerPinsTimeZone() throws {
        let seoul = try #require(TimeZone(identifier: "Asia/Seoul"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul

        // `nextTriggerDate()` only answers for a moment still ahead, so this is anchored to now
        // rather than to a fixed date that would quietly stop testing anything once it passed.
        let instant = try #require(calendar.date(
            byAdding: .day, value: 30, to: ReminderService.minuteDate(Date())))
        let components = ReminderService.triggerComponents(for: instant, calendar: calendar)
        #expect(components.timeZone == seoul)

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        #expect(trigger.nextTriggerDate() == instant)

        // The same components read from a different zone still name the same instant.
        var elsewhere = Calendar(identifier: .gregorian)
        elsewhere.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(elsewhere.date(from: components) == instant)
    }

    @Test("Scheduling through the service carries the time zone into the trigger")
    func scheduledTriggerCarriesTimeZone() async throws {
        let (directory, store, n, t, i) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FakeReminderClient()
        let service = ReminderService(client: client)
        let saved = try await service.saveReminder(
            store: store, noteID: n, tabID: t, itemID: i, date: Date().addingTimeInterval(600))

        let trigger = try #require(client.requests[i.uuidString]?.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.timeZone == TimeZone.current)
        #expect(trigger.nextTriggerDate() == saved)
    }

    /// The body macOS keeps on the lock screen and in its notification database. Pure, so the
    /// preview setting is exercised in both positions without writing to the real defaults.
    @Test("The notification body only carries the task's own words when the preview is on")
    func bodyFollowsPreviewSetting() {
        let reminder = ReminderService.Reminder(id: UUID(), title: "치과 예약 확인", date: Date())
        for language in [AppLanguage.korean, .english] {
            #expect(ReminderService.notificationBody(
                for: reminder, showsPreview: true, language: language) == "치과 예약 확인")

            let hidden = ReminderService.notificationBody(
                for: reminder, showsPreview: false, language: language)
            #expect(hidden == L("예약해 둔 할 일이 있어요", language: language))
            #expect(!hidden.contains("치과"))
        }
    }

    /// Flipping the setting has to rewrite requests that are already queued. The duplicate check
    /// used to compare against the task title, so an existing notification kept its old body
    /// until the memo happened to change.
    @Test("Turning the preview on rewrites an already scheduled notification")
    func previewSettingRewritesPendingRequest() async throws {
        let (directory, store, n, t, i) = try fixture()
        let settings = AppSettings.shared
        let previous = settings.showsReminderPreview
        defer {
            settings.showsReminderPreview = previous
            try? FileManager.default.removeItem(at: directory)
        }

        settings.showsReminderPreview = false
        let client = FakeReminderClient()
        let service = ReminderService(client: client)
        let date = try await service.saveReminder(
            store: store, noteID: n, tabID: t, itemID: i, date: Date().addingTimeInterval(600))
        #expect(client.requests[i.uuidString]?.content.body == L("예약해 둔 할 일이 있어요"))

        settings.showsReminderPreview = true
        #expect(await service.retrySynchronization(for: store.notes) == nil)
        #expect(client.requests[i.uuidString]?.content.body == "예약 테스트")

        // Same identifier, so the queue is replaced rather than duplicated, and the fire time
        // survives the rewrite.
        #expect(client.requests.count == 1)
        let trigger = try #require(client.requests[i.uuidString]?.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.nextTriggerDate() == date)
    }
}
