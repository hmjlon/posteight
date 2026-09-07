import Foundation
import Testing
@testable import Posteight

@Suite("Reminder persistence", .serialized)
@MainActor
struct ReminderPersistenceTests {
    @Test("Merging preserves every tab, selection, contents and reminder after reload")
    func mergeRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let targetID = store.addNote()
        let sourceID = store.addNote()
        let tabID = try #require(store.addTab(to: sourceID))
        let itemID = try #require(store.addItem(to: sourceID, tabID: tabID))
        store.updateItemTitle(noteID: sourceID, tabID: tabID, itemID: itemID, title: "배포 준비")
        store.updateItemDetail(noteID: sourceID, tabID: tabID, itemID: itemID, detail: "변경 확인")
        store.setReminder(noteID: sourceID, tabID: tabID, itemID: itemID, date: Date().addingTimeInterval(600))
        let source = try #require(store.notes.first { $0.id == sourceID })
        let target = try #require(store.notes.first { $0.id == targetID })
        #expect(store.mergeNotes(from: sourceID, into: targetID))
        let reloaded = PosteightStore(directory: directory)
        let merged = try #require(reloaded.notes.first { $0.id == targetID })
        #expect(merged.tabs == target.tabs + source.tabs)
        #expect(merged.selectedTabID == tabID)
        #expect(merged.paperHex == target.paperHex)
        #expect(!reloaded.notes.contains { $0.id == sourceID })
        #expect(!reloaded.trashedNotes.contains { $0.id == sourceID })
        #expect(ReminderService.reminders(in: [merged]).map(\.id) == [itemID])
    }

    @Test("Completion, deletion and trash cancel reminders, future restores retain them")
    func reminderLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let id = store.addNote()
        let tabID = try #require(store.notes.first { $0.id == id }?.selectedTabID)
        let itemID = try #require(store.addItem(to: id, tabID: tabID))
        store.updateItemTitle(noteID: id, tabID: tabID, itemID: itemID, title: "예약 확인")
        let date = Date().addingTimeInterval(600)
        store.setReminder(noteID: id, tabID: tabID, itemID: itemID, date: date)
        #expect(ReminderService.reminders(in: store.notes).map(\.id) == [itemID])
        store.toggleItem(noteID: id, tabID: tabID, itemID: itemID)
        #expect(ReminderService.reminders(in: store.notes).isEmpty)
        store.toggleItem(noteID: id, tabID: tabID, itemID: itemID)
        store.moveNoteToTrash(id)
        #expect(ReminderService.reminders(in: store.notes).isEmpty)
        store.restoreNote(id)
        #expect(ReminderService.reminders(in: store.notes).map(\.id) == [itemID])
        #expect(ReminderService.reminders(in: store.notes, now: date.addingTimeInterval(1)).isEmpty)
        store.setReminder(noteID: id, tabID: tabID, itemID: itemID, date: nil)
        #expect(ReminderService.reminders(in: store.notes).isEmpty)
        store.setReminder(noteID: id, tabID: tabID, itemID: itemID, date: date)
        store.deleteItem(noteID: id, tabID: tabID, itemID: itemID)
        #expect(ReminderService.reminders(in: store.notes).isEmpty)
    }

    @Test("Version one items without reminder fields still decode")
    func oldItem() throws {
        let item = TodoItem(title: "이전 메모")
        let data = try JSONEncoder().encode(item)
        #expect(!String(decoding: data, as: UTF8.self).contains("reminderAt"))
        #expect(try JSONDecoder().decode(TodoItem.self, from: data).reminderAt == nil)
    }
}
