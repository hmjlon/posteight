import Foundation
import Testing
@testable import Posteight

@Suite(.serialized)
@MainActor
struct EditingHistoryTests {
    private func withStore(_ body: (PosteightStore, UUID, UUID, UUID) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let id = store.addNote()
        let tab = try #require(store.notes.first { $0.id == id }?.selectedTab)
        store.clearEditingHistory()
        try body(store, id, tab.id, try #require(tab.items.first?.id))
    }

    @Test func undoCrossesRowsInReverseOrder() throws {
        try withStore { store, note, tab, first in
            store.updateItemTitle(noteID: note, tabID: tab, itemID: first, title: "1")
            store.endTextUndoGroup()
            let second = try #require(store.addItem(to: note, tabID: tab))
            store.updateItemTitle(noteID: note, tabID: tab, itemID: second, title: "2")
            #expect(store.undo())
            #expect(store.itemTitle(noteID: note, tabID: tab, itemID: second) == nil)
            #expect(store.itemTitle(noteID: note, tabID: tab, itemID: first) == "1")
            #expect(store.undo())
            #expect(store.itemTitle(noteID: note, tabID: tab, itemID: first) == "")
            #expect(!store.undo())
            #expect(store.redo())
            #expect(store.redo())
            #expect(store.itemTitle(noteID: note, tabID: tab, itemID: second) == "2")
        }
    }

    @Test func closingTabRestoresItsPositionContentsAndSelectionBeforeUndoingText() throws {
        try withStore { store, note, firstTab, item in
            let secondTab = try #require(store.addTab(to: note))
            store.selectTab(noteID: note, tabID: firstTab)
            store.clearEditingHistory()
            store.updateItemTitle(noteID: note, tabID: firstTab, itemID: item, title: "1")
            #expect(store.moveTabToTrash(noteID: note, tabID: firstTab))
            #expect(store.undo())
            let restored = try #require(store.notes.first { $0.id == note })
            #expect(restored.tabs.map(\.id) == [firstTab, secondTab])
            #expect(restored.selectedTabID == firstTab)
            #expect(restored.tabs[0].items[0].title == "1")
            #expect(!store.trashedTabs.contains { $0.id == firstTab })
            #expect(store.undo())
            #expect(store.itemTitle(noteID: note, tabID: firstTab, itemID: item) == "")
            #expect(store.redo())
            #expect(store.redo())
            #expect(store.trashedTabs.filter { $0.id == firstTab }.count == 1)
        }
    }

    @Test func deletionIsSeparateFromTypingAndNewEditsDiscardRedo() throws {
        try withStore { store, note, tab, item in
            store.updateItemTitle(noteID: note, tabID: tab, itemID: item, title: "1")
            store.updateItemTitle(noteID: note, tabID: tab, itemID: item, title: "12")
            store.updateItemTitle(noteID: note, tabID: tab, itemID: item, title: "")
            #expect(store.undo())
            #expect(store.itemTitle(noteID: note, tabID: tab, itemID: item) == "12")
            store.updateItemTitle(noteID: note, tabID: tab, itemID: item, title: "123")
            #expect(!store.redo())
        }
    }

    @Test func closingLastWindowSharesTheSameHistory() throws {
        try withStore { store, note, tab, item in
            store.updateItemTitle(noteID: note, tabID: tab, itemID: item, title: "1")
            store.recordClosedWindow(note)
            #expect(store.undo())
            #expect(store.historyWindowRequest?.noteID == note)
            #expect(store.historyWindowRequest?.show == true)
            #expect(store.itemTitle(noteID: note, tabID: tab, itemID: item) == "1")
            #expect(store.redo())
            #expect(store.historyWindowRequest?.show == false)
        }
    }

    @Test func historyDoesNotRewindLayoutOrResurrectPermanentlyDeletedData() throws {
        try withStore { store, note, tab, item in
            store.updateItemTitle(noteID: note, tabID: tab, itemID: item, title: "1")
            let position = NotePoint(x: 700, y: 500)
            store.updateNotePosition(note, position: position)
            #expect(store.undo())
            #expect(store.notes.first { $0.id == note }?.position == position)
            store.moveNoteToTrash(note)
            store.permanentlyDeleteNote(note)
            #expect(!store.undo())
            #expect(!store.redo())
        }
    }

    @Test func restoredContentsAreSaved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let note = store.addNote()
        let tab = try #require(store.addTab(to: note))
        store.moveTabToTrash(noteID: note, tabID: tab)
        #expect(store.undo())
        let loaded = PosteightStore(directory: directory)
        #expect(loaded.notes == store.notes)
        #expect(loaded.trashedTabs == store.trashedTabs)
    }
}
