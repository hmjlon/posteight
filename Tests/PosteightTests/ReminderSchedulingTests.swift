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
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FakeReminderClient()
        client.status = .notDetermined
        let service = ReminderService(client: client)
        let chosen = Date().addingTimeInterval(600)
        let saved = try await service.saveReminder(store: store, noteID: n, tabID: t, itemID: i, date: chosen)
        let request = try #require(client.requests[i.uuidString])
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.second == 0)
        #expect(!trigger.repeats)
        #expect(request.content.body == "예약 테스트")
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
}
