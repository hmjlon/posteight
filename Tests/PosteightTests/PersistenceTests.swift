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

    @Test("각 탭의 아이콘을 독립적으로 바꾸고 저장한다")
    func tabStickersAreIndependentAndPersistent() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let firstTabID = try memo(store, id: noteID).selectedTabID
        let secondTabID = try #require(store.addTab(to: noteID))

        store.updateTabSticker(noteID: noteID, tabID: firstTabID, symbol: "briefcase")
        store.updateTabSticker(noteID: noteID, tabID: secondTabID, symbol: "house")
        store.flush()

        let reloaded = PosteightStore(directory: directory)
        let tabs = try memo(reloaded, id: noteID).tabs
        #expect(tabs.first { $0.id == firstTabID }?.stickerSymbol == "briefcase")
        #expect(tabs.first { $0.id == secondTabID }?.stickerSymbol == "house")
    }

    @Test("Closing a tab that isn't selected leaves the current one open")
    func closingOtherTabKeepsSelection() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let firstTabID = try memo(store, id: noteID).selectedTabID
        let secondTabID = try #require(store.addTab(to: noteID))
        store.selectTab(noteID: noteID, tabID: firstTabID)

        #expect(store.moveTabToTrash(noteID: noteID, tabID: secondTabID))

        let note = try memo(store, id: noteID)
        #expect(note.tabs.map(\.id) == [firstTabID])
        #expect(note.selectedTabID == firstTabID)
        #expect(store.trashedTabs.map(\.id) == [secondTabID])
    }

    @Test("Closing the selected tab lands on the neighbor that takes its place")
    func closingSelectedTabLandsOnNeighbor() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let firstTabID = try memo(store, id: noteID).selectedTabID
        let secondTabID = try #require(store.addTab(to: noteID))
        let thirdTabID = try #require(store.addTab(to: noteID))
        store.selectTab(noteID: noteID, tabID: secondTabID)

        #expect(store.moveTabToTrash(noteID: noteID, tabID: secondTabID))

        let note = try memo(store, id: noteID)
        #expect(note.tabs.map(\.id) == [firstTabID, thirdTabID])
        #expect(note.selectedTabID == thirdTabID)
    }

    @Test("A memo's last tab cannot be closed")
    func lastTabSurvivesClosing() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let onlyTabID = try memo(store, id: noteID).selectedTabID

        #expect(!store.moveTabToTrash(noteID: noteID, tabID: onlyTabID))
        #expect(try memo(store, id: noteID).tabs.map(\.id) == [onlyTabID])
        #expect(store.trashedTabs.isEmpty)
    }

    @Test("Restoring a closed tab puts it back in its note")
    func restoringTabReturnsToItsNote() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let firstTabID = try memo(store, id: noteID).selectedTabID
        let secondTabID = try #require(store.addTab(to: noteID))
        store.moveTabToTrash(noteID: noteID, tabID: secondTabID)

        store.restoreTab(secondTabID)

        #expect(store.trashedTabs.isEmpty)
        let note = try memo(store, id: noteID)
        #expect(note.tabs.map(\.id) == [firstTabID, secondTabID])
        #expect(note.selectedTabID == secondTabID)
    }

    @Test("Restoring a tab whose note is gone stands up a new one instead of losing it")
    func restoringTabRecreatesNoteWhenOriginalIsGone() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let secondTabID = try #require(store.addTab(to: noteID))
        store.moveTabToTrash(noteID: noteID, tabID: secondTabID)
        store.moveNoteToTrash(noteID)

        store.restoreTab(secondTabID)

        #expect(store.trashedTabs.isEmpty)
        let notes = store.notes.filter { $0.tabs.contains { $0.id == secondTabID } }
        #expect(notes.count == 1)
        #expect(notes.first?.tabs.map(\.id) == [secondTabID])
    }

    @Test("Emptying the trash clears closed tabs too")
    func emptyingTrashClearsTabs() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let secondTabID = try #require(store.addTab(to: noteID))
        store.moveTabToTrash(noteID: noteID, tabID: secondTabID)

        store.emptyTrash()

        #expect(store.trashedTabs.isEmpty)
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
