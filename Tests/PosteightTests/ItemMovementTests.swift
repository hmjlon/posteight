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

    @Test func completionGroupingTogglesBackToTheOriginalOrderAndKeepsNewRows() throws {
        try withStore { store, directory in
            let note = store.addNote()
            let tab = try #require(store.notes.first(where: { $0.id == note })?.selectedTab)
            let firstEmpty = try #require(tab.items.first?.id)
            let doneOne = try #require(store.addItem(to: note, tabID: tab.id))
            let pendingOne = try #require(store.addItem(to: note, tabID: tab.id))
            let doneTwo = try #require(store.addItem(to: note, tabID: tab.id))
            let pendingTwo = try #require(store.addItem(to: note, tabID: tab.id))
            let lastEmpty = try #require(store.addItem(to: note, tabID: tab.id))

            store.updateItemTitle(noteID: note, tabID: tab.id, itemID: doneOne, title: "완료 1")
            store.toggleItem(noteID: note, tabID: tab.id, itemID: doneOne)
            store.updateItemTitle(noteID: note, tabID: tab.id, itemID: pendingOne, title: "미완료 1")
            store.updateItemTitle(noteID: note, tabID: tab.id, itemID: doneTwo, title: "완료 2")
            store.toggleItem(noteID: note, tabID: tab.id, itemID: doneTwo)
            store.updateItemTitle(noteID: note, tabID: tab.id, itemID: pendingTwo, title: "미완료 2")

            let before = try #require(store.movementTab(noteID: note, tabID: tab.id)?.items)
            store.clearEditingHistory()
            #expect(!store.isCompletionGroupingActive(noteID: note, tabID: tab.id))
            #expect(store.toggleItemsByCompletion(noteID: note, tabID: tab.id))
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [
                pendingOne, pendingTwo, doneOne, doneTwo, firstEmpty, lastEmpty
            ])
            #expect(store.isCompletionGroupingActive(noteID: note, tabID: tab.id))

            store.flush()
            let restarted = PosteightStore(directory: directory)
            #expect(restarted.isCompletionGroupingActive(noteID: note, tabID: tab.id))
            let addedAfterSorting = try #require(restarted.addItem(to: note, tabID: tab.id))
            #expect(restarted.toggleItemsByCompletion(noteID: note, tabID: tab.id))
            #expect(restarted.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) ==
                before.map(\.id) + [addedAfterSorting])
            #expect(!restarted.isCompletionGroupingActive(noteID: note, tabID: tab.id))
            #expect(restarted.undo())
            #expect(restarted.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [
                pendingOne, pendingTwo, doneOne, doneTwo, firstEmpty, lastEmpty, addedAfterSorting
            ])
            #expect(restarted.redo())
            #expect(restarted.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) ==
                before.map(\.id) + [addedAfterSorting])
        }
    }

    @Test func pinnedItemStaysAtTheTopAcrossSortingDraggingPersistenceAndUndo() throws {
        try withStore { store, directory in
            let note = store.addNote()
            let tab = try #require(store.notes.first(where: { $0.id == note })?.selectedTab)
            let first = try #require(tab.items.first?.id)
            store.updateItemTitle(noteID: note, tabID: tab.id, itemID: first, title: "일반 1")
            let pinned = try #require(store.addItem(to: note, tabID: tab.id))
            store.updateItemTitle(noteID: note, tabID: tab.id, itemID: pinned, title: "고정")
            let last = try #require(store.addItem(to: note, tabID: tab.id))
            store.updateItemTitle(noteID: note, tabID: tab.id, itemID: last, title: "일반 2")

            store.clearEditingHistory()
            store.toggleItemPin(noteID: note, tabID: tab.id, itemID: pinned)
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [pinned, first, last])
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.first?.isPinned == true)
            #expect(store.undo())
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [first, pinned, last])
            #expect(store.redo())

            store.toggleItem(noteID: note, tabID: tab.id, itemID: pinned)
            store.toggleItem(noteID: note, tabID: tab.id, itemID: first)
            #expect(store.toggleItemsByCompletion(noteID: note, tabID: tab.id))
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.first?.id == pinned)
            let drag = TodoItemDrag(noteID: note, tabID: tab.id, itemID: last)
            #expect(!store.moveItem(drag, toNote: note, tab: tab.id, before: pinned))
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.first?.id == pinned)

            store.flush()
            let restarted = PosteightStore(directory: directory)
            #expect(restarted.movementTab(noteID: note, tabID: tab.id)?.items.first?.isPinned == true)
        }
    }

    /// 고정 항목 앞자리는 `itemsPinnedFirst` 정규화가 되돌리기 때문에 `moveItem` 이 조용히
    /// 거절한다. 삽입선을 그리기 전에 같은 답이 나와야 사용자가 헛손질을 하지 않는다.
    @Test func aDropAboveAPinIsRefusedBeforeTheInsertionLineIsDrawn() throws {
        try withStore { store, _ in
            let note = store.addNote()
            let tab = try #require(store.notes.first(where: { $0.id == note })?.selectedTab)
            let pinned = try #require(tab.items.first?.id)
            store.updateItemTitle(noteID: note, tabID: tab.id, itemID: pinned, title: "고정")
            let plain = try #require(store.addItem(to: note, tabID: tab.id))
            store.updateItemTitle(noteID: note, tabID: tab.id, itemID: plain, title: "보통")
            store.toggleItemPin(noteID: note, tabID: tab.id, itemID: pinned)
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [pinned, plain])

            let plainDrag = TodoItemDrag(noteID: note, tabID: tab.id, itemID: plain)
            // 거절하는 답과 실제 결과가 같아야 한다. 어긋나면 삽입선이 거짓말을 한다.
            #expect(!store.canMoveItem(plainDrag, toNote: note, tab: tab.id, before: pinned))
            #expect(!store.moveItem(plainDrag, toNote: note, tab: tab.id, before: pinned))

            // 맨 뒤에 붙이는 드롭(탭 헤더, 목록 끝의 빈 줄)은 정규화와 다툴 일이 없다.
            #expect(store.canMoveItem(plainDrag, toNote: note, tab: tab.id, before: nil))

            // 고정된 항목끼리는 서로 앞뒤로 옮길 수 있다.
            let second = try #require(store.addItem(to: note, tabID: tab.id))
            store.updateItemTitle(noteID: note, tabID: tab.id, itemID: second, title: "고정 둘")
            store.toggleItemPin(noteID: note, tabID: tab.id, itemID: second)
            let pinnedDrag = TodoItemDrag(noteID: note, tabID: tab.id, itemID: second)
            #expect(store.canMoveItem(pinnedDrag, toNote: note, tab: tab.id, before: pinned))
            #expect(store.moveItem(pinnedDrag, toNote: note, tab: tab.id, before: pinned))
            #expect(store.movementTab(noteID: note, tabID: tab.id)?.items.map(\.id) == [second, pinned, plain])

            // 고정 안 된 행 앞은 그대로 받는다.
            #expect(store.canMoveItem(pinnedDrag, toNote: note, tab: tab.id, before: plain))
        }
    }
}

private extension PosteightStore {
    func movementTab(noteID: UUID, tabID: UUID) -> MemoTab? {
        notes.first { $0.id == noteID }?.tabs.first { $0.id == tabID }
    }
}
