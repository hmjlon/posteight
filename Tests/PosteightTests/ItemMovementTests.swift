import Foundation
import Testing
@testable import Posteight

@Suite(.serialized)
@MainActor
struct ItemMovementTests {
    private func withStore(_ body: (PosteightStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        try body(store, directory)
    }

    @Test func reorderBothDirectionsAndAppendWithUndo() throws {
        try withStore { store, _ in
            let note = store.addNote()
            let tab = try #require(store.notes.first(where: { $0.id == note })?.selectedTab)
            let first = try #require(tab.items.first?.id)
            let second = try #require(store.addItem(to: note, tabID: tab.id))
            let third = try #require(store.addItem(to: note, tabID: tab.id))
            let drag = TodoItemDrag(noteID: note, tabID: tab.id, itemID: third)
            store.clearEditingHistory()
            #expect(store.moveItem(drag, toNote: note, tab: tab.id, before: first))
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [third, first, second])
            #expect(store.moveItem(drag, toNote: note, tab: tab.id, before: second))
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [first, third, second])
            #expect(store.moveItem(drag, toNote: note, tab: tab.id))
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [first, second, third])
            #expect(store.undo())
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [first, third, second])
            #expect(store.redo())
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [first, second, third])
        }
    }

    @Test func crossNoteMovePreservesEntireItemAndPersists() throws {
        try withStore { store, directory in
            let source = store.addNote()
            let sourceTab = try #require(store.notes.first(where: { $0.id == source })?.selectedTab)
            let itemID = try #require(sourceTab.items.first?.id)
            store.updateItemTitle(noteID: source, tabID: sourceTab.id, itemID: itemID, title: "옮길 일")
            store.updateItemDetail(noteID: source, tabID: sourceTab.id, itemID: itemID, detail: "상세 내용")
            store.toggleItem(noteID: source, tabID: sourceTab.id, itemID: itemID)
            store.setReminder(noteID: source, tabID: sourceTab.id, itemID: itemID, date: Date(timeIntervalSince1970: 2_000_000_000))
            let original = try #require(store.movementTab(noteID: source, tabID: sourceTab.id)?.items.first)
            let target = store.addNote()
            let targetTab = try #require(store.notes.first(where: { $0.id == target })?.selectedTab)
            for item in targetTab.items { store.deleteItem(noteID: target, tabID: targetTab.id, itemID: item.id) }
            store.clearEditingHistory()
            let before = store.notes
            let drag = TodoItemDrag(noteID: source, tabID: sourceTab.id, itemID: itemID)
            #expect(store.moveItem(drag, toNote: target, tab: targetTab.id))
            #expect(store.movementTab(noteID: source, tabID: sourceTab.id)?.items.isEmpty == true)
            #expect(store.movementTab(noteID: target, tabID: targetTab.id)?.items == [original])
            #expect(store.undo())
            #expect(store.notes == before)
            #expect(!store.canUndo)
            #expect(store.redo())
            store.flush()
            let restored = PosteightStore(directory: directory)
            #expect(restored.movementTab(noteID: target, tabID: targetTab.id)?.items == [original])
            #expect(restored.movementTab(noteID: source, tabID: sourceTab.id)?.items.isEmpty == true)
        }
    }

    @Test func moveBetweenTabsInSameNoteUsesLiveSourceAndKeepsReminder() throws {
        try withStore { store, _ in
            let note = store.addNote()
            let sourceTab = try #require(store.notes.first(where: { $0.id == note })?.selectedTab)
            let itemID = try #require(sourceTab.items.first?.id)
            let targetTab = try #require(store.addTab(to: note))
            let targetItem = try #require(store.movementTab(noteID: note, tabID: targetTab)?.items.first?.id)
            let drag = TodoItemDrag(noteID: note, tabID: sourceTab.id, itemID: itemID)
            store.updateItemTitle(noteID: note, tabID: sourceTab.id, itemID: itemID, title: "드래그 시작 후 편집")
            store.setReminder(noteID: note, tabID: sourceTab.id, itemID: itemID, date: Date(timeIntervalSince1970: 2_000_000_000))
            let original = try #require(store.movementTab(noteID: note, tabID: sourceTab.id)?.items.first)
            #expect(store.moveItem(drag, toNote: note, tab: targetTab, before: targetItem))
            #expect(store.movementTab(noteID: note, tabID: targetTab)?.items.first == original)
            #expect(store.movementTab(noteID: note, tabID: sourceTab.id)?.items.isEmpty == true)
            #expect(!store.moveItem(drag, toNote: note, tab: targetTab))
            #expect(store.movementTab(noteID: note, tabID: targetTab)?.items.count == 2)
        }
    }

    @Test func invalidAndNoOpDropsDoNotChangeDataOrHistory() throws {
        try withStore { store, _ in
            let note = store.addNote()
            let tab = try #require(store.notes.first(where: { $0.id == note })?.selectedTab)
            let itemID = try #require(tab.items.first?.id)
            let drag = TodoItemDrag(noteID: note, tabID: tab.id, itemID: itemID)
            store.clearEditingHistory()
            let before = store.notes
            #expect(!store.moveItem(drag, toNote: UUID(), tab: tab.id))
            #expect(!store.moveItem(drag, toNote: note, tab: UUID()))
            #expect(!store.moveItem(drag, toNote: note, tab: tab.id, before: UUID()))
            #expect(!store.moveItem(drag, toNote: note, tab: tab.id, before: itemID))
            #expect(!store.moveItem(drag, toNote: note, tab: tab.id))
            #expect(!store.moveItem(TodoItemDrag(noteID: note, tabID: tab.id, itemID: UUID()), toNote: note, tab: tab.id))
            #expect(store.notes == before)
            #expect(!store.canUndo)
        }
    }
}

private extension PosteightStore {
    func movementTab(noteID: UUID, tabID: UUID) -> MemoTab? {
        notes.first { $0.id == noteID }?.tabs.first { $0.id == tabID }
    }
}
