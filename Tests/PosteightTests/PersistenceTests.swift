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

    private func mode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue
    }

    /// Notes are plain JSON at a fixed path. The default `0755`/`0644` leaves them readable by
    /// anything else running as this user.
    @Test("A fresh store is created private to the user")
    func fileModes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        store.flush()

        #expect(try mode(directory) == 0o700)
        for name in ["notes.json", "trash.json", "trashed-tabs.json"] {
            #expect(try mode(directory.appendingPathComponent(name)) == 0o600, "\(name)")
        }
    }

    /// An install that predates this already has a `0755` directory, and `createDirectory`
    /// ignores its attributes once the directory exists.
    @Test("An already wide store is narrowed on the next save")
    func existingStoreIsNarrowed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o755])

        let store = PosteightStore(directory: directory)
        store.flush()
        #expect(try mode(directory) == 0o700)
    }

    /// Turning on the sandbox moves Application Support into the container, and macOS does not
    /// migrate this app's folder for us. Getting this wrong looks to the user exactly like the
    /// upgrade having thrown every note away.
    @Test("An install from before the sandbox is copied into the container")
    func legacyStoreIsMigrated() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("legacy")
        let container = root.appendingPathComponent("container")

        let old = PosteightStore(directory: legacy)
        let noteID = old.addNote()
        old.updateTabTitle(noteID: noteID, tabID: try memo(old, id: noteID).selectedTabID,
                           title: "샌드박스 이전 메모")
        old.moveNoteToTrash(old.addNote())
        old.flush()
        // The font library keeps its own folder under the store, and it travels too.
        let fonts = legacy.appendingPathComponent("Fonts")
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: fonts.appendingPathComponent("manifest.json"))

        #expect(PosteightStore.migrateStore(from: legacy, to: container))

        let migrated = PosteightStore(directory: container)
        #expect(try memo(migrated, id: noteID).tabs.first?.title == "샌드박스 이전 메모")
        #expect(migrated.trashedNotes.count == 1)
        #expect(FileManager.default.fileExists(
            atPath: container.appendingPathComponent("Fonts/manifest.json").path))

        // Copied, not moved: rolling this release back has to leave the old install usable.
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("notes.json").path))

        // And the copy does not carry the old 0644 into the container.
        #expect(try mode(container.appendingPathComponent("notes.json")) == 0o600)
        #expect(try mode(container.appendingPathComponent("Fonts")) == 0o700)
        #expect(try mode(container.appendingPathComponent("Fonts/manifest.json")) == 0o600)
    }

    /// Running twice would overwrite whatever the user has done since the upgrade.
    @Test("Migration does not run a second time")
    func migrationRunsOnce() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("legacy")
        let container = root.appendingPathComponent("container")

        let old = PosteightStore(directory: legacy)
        let legacyNote = old.addNote()
        old.flush()
        #expect(PosteightStore.migrateStore(from: legacy, to: container))

        // What the user did after the upgrade.
        let migrated = PosteightStore(directory: container)
        migrated.moveNoteToTrash(legacyNote)
        let freshNote = migrated.addNote()
        migrated.flush()

        #expect(!PosteightStore.migrateStore(from: legacy, to: container))
        let reloaded = PosteightStore(directory: container)
        // A second run would put the deleted note back and lose the new one.
        #expect(!reloaded.notes.contains { $0.id == legacyNote })
        #expect(reloaded.trashedNotes.map(\.id) == [legacyNote])
        #expect(reloaded.notes.contains { $0.id == freshNote })
    }

    @Test("Nothing to migrate leaves the container untouched")
    func migrationWithoutALegacyStore() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("container")

        #expect(!PosteightStore.migrateStore(from: root.appendingPathComponent("missing"), to: container))
        #expect(!FileManager.default.fileExists(atPath: container.path))

        // An empty but existing folder is not a store either.
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(!PosteightStore.migrateStore(from: empty, to: container))
    }

    /// An unsandboxed build resolves both paths to the same folder, and copying a store onto
    /// itself would be a very bad way to find that out.
    @Test("The legacy path is the real home, not the container")
    func legacyPathPointsAtTheRealHome() throws {
        let legacy = try #require(PosteightStore.legacyStoreDirectory)
        #expect(legacy.path.hasSuffix("/Library/Application Support/Posteight"))
        #expect(!legacy.path.contains("/Library/Containers/"))
        // `swift test` is unbundled, so there is no container and the two coincide — which is
        // exactly the condition `storeDirectory` uses to skip the migration entirely.
        #expect(legacy == PosteightStore.storeDirectory)
    }

    /// `Data.write(options: .atomic)` replaces the file rather than writing through it, so this
    /// pins down that the replacement keeps the mode stamped at creation.
    @Test("Later saves do not widen the files again")
    func modeSurvivesRewrite() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        store.flush()

        let noteID = store.addNote()
        store.updateTabTitle(noteID: noteID, tabID: try memo(store, id: noteID).selectedTabID,
                             title: "두 번째 저장")
        store.flush()

        #expect(try mode(directory.appendingPathComponent("notes.json")) == 0o600)
    }
}
