import Foundation
import Testing

@testable import Posteight

@Suite("Persistence", .serialized)
@MainActor
struct PersistenceTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("posteight-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func memo(_ store: PosteightStore, id: UUID) throws -> StickyNote {
        try #require(store.notes.first { $0.id == id })
    }

    @Test("Flushing writes a memo and its selected tab content")
    func roundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let tabID = try memo(store, id: noteID).selectedTabID
        store.updateTabTitle(noteID: noteID, tabID: tabID, title: "저장 확인")
        store.flush()

        let reloaded = PosteightStore(directory: directory)
        #expect(try memo(reloaded, id: noteID).selectedTab?.title == "저장 확인")
        #expect(reloaded.notes.count == store.notes.count)
    }

    @Test("Trashed memos survive a reload too")
    func trashRoundTrip() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        store.moveNoteToTrash(noteID)
        store.flush()

        let reloaded = PosteightStore(directory: directory)
        #expect(reloaded.trashedNotes.contains { $0.id == noteID })
        #expect(!reloaded.notes.contains { $0.id == noteID })
    }

    @Test("A save lands without an explicit flush once the debounce elapses")
    func debouncedSave() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let tabID = try memo(store, id: noteID).selectedTabID
        store.updateTabTitle(noteID: noteID, tabID: tabID, title: "디바운스")
        try await Task.sleep(for: .seconds(1))

        let reloaded = PosteightStore(directory: directory)
        #expect(try memo(reloaded, id: noteID).selectedTab?.title == "디바운스")
    }

    @Test("A new memo starts with one selected default tab")
    func newMemoHasDefaultTab() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let note = try memo(store, id: store.addNote())
        #expect(note.tabs.count == 1)
        #expect(note.selectedTabID == note.tabs[0].id)
        #expect(note.tabs[0].name == "메모 1")
    }

    @Test("Adding tabs changes only the target memo and activates the new tab")
    func tabsStayInsideTheirMemo() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let firstID = store.addNote()
        let secondID = store.addNote()
        let newTabID = try #require(store.addTab(to: firstID))

        let first = try memo(store, id: firstID)
        let second = try memo(store, id: secondID)
        #expect(first.tabs.map(\.name) == ["메모 1", "메모 2"])
        #expect(first.selectedTabID == newTabID)
        #expect(second.tabs.map(\.name) == ["메모 1"])
        #expect(!second.tabs.contains { $0.id == newTabID })
    }

    @Test("Selecting and renaming a tab does not mutate its sibling memo")
    func selectionAndNameAreMemoScoped() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let firstID = store.addNote()
        let secondID = store.addNote()
        let firstOriginalTabID = try memo(store, id: firstID).selectedTabID
        let secondOriginalTabID = try memo(store, id: secondID).selectedTabID
        _ = store.addTab(to: firstID)

        store.selectTab(noteID: firstID, tabID: firstOriginalTabID)
        store.updateTabName(noteID: firstID, tabID: firstOriginalTabID, name: "업무")
        store.updateTabName(noteID: firstID, tabID: firstOriginalTabID, name: "   ")

        #expect(try memo(store, id: firstID).selectedTabID == firstOriginalTabID)
        #expect(store.tabName(noteID: firstID, tabID: firstOriginalTabID) == "업무")
        #expect(try memo(store, id: secondID).selectedTabID == secondOriginalTabID)
        #expect(store.tabName(noteID: secondID, tabID: secondOriginalTabID) == "메모 1")
    }

    @Test("A blank placeholder item cannot be completed")
    func blankItemDoesNotComplete() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let tab = try #require(memo(store, id: noteID).selectedTab)
        let itemID = try #require(tab.items.first?.id)
        store.toggleItem(noteID: noteID, tabID: tab.id, itemID: itemID)

        let item = try #require(memo(store, id: noteID).selectedTab?.items.first)
        #expect(!item.isDone)
        #expect(item.completedAt == nil)
    }

    @Test("Clearing a completed item also clears its completion")
    func clearingItemResetsCompletion() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let tab = try #require(memo(store, id: noteID).selectedTab)
        let itemID = try #require(tab.items.first?.id)
        store.updateItemTitle(noteID: noteID, tabID: tab.id, itemID: itemID, title: "완료할 일")
        store.toggleItem(noteID: noteID, tabID: tab.id, itemID: itemID)
        store.updateItemTitle(noteID: noteID, tabID: tab.id, itemID: itemID, title: "   ")

        let item = try #require(memo(store, id: noteID).selectedTab?.items.first)
        #expect(!item.isDone)
        #expect(item.completedAt == nil)
    }

    @Test("Multiple tabs and the active selection survive a reload")
    func tabsRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let tabID = try #require(store.addTab(to: noteID))
        store.updateTabName(noteID: noteID, tabID: tabID, name: "개인")
        store.flush()

        let reloaded = PosteightStore(directory: directory)
        let note = try memo(reloaded, id: noteID)
        #expect(note.tabs.map(\.name) == ["메모 1", "개인"])
        #expect(note.selectedTabID == tabID)
    }
}
