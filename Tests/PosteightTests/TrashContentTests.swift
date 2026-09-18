import Foundation
import Testing
@testable import Posteight

@Suite("Trash content")
struct TrashContentTests {
    @Test("Empty input rows do not count as tasks or appear in previews")
    func emptyRows() {
        let items = [TodoItem(title: ""), TodoItem(title: " \n\t"), TodoItem(title: "실제 할 일")]
        #expect(items.filter(\.hasTitle).map(\.title) == ["실제 할 일"])
        #expect(items.filter(\.hasContent).map(\.title) == ["실제 할 일"])
    }

    @Test("User-entered placeholder wording is still real content")
    func literalPlaceholder() {
        #expect(TodoItem(title: "할 일 입력").hasTitle)
        #expect(TodoItem(title: "New item").hasTitle)
    }

    @Test("Details remain visible after clearing a title but do not count as a task")
    func detailOnly() {
        let item = TodoItem(title: " ", detail: "남겨 둔 댓글")
        #expect(!item.hasTitle)
        #expect(item.hasContent)
        #expect(!TodoItem(title: "", detail: " \n").hasContent)
    }

    @MainActor
    private func retentionFixture() throws -> (URL, PosteightStore, UUID) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("posteight-tests-\(UUID().uuidString)", isDirectory: true)
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let tabID = try #require(store.notes.first { $0.id == noteID }?.selectedTabID)
        #expect(store.addTab(to: noteID) != nil)
        #expect(store.moveTabToTrash(noteID: noteID, tabID: tabID))
        store.moveNoteToTrash(noteID)
        #expect(store.trashedNotes.count == 1)
        #expect(store.trashedTabs.count == 1)
        return (directory, store, noteID)
    }

    private var retention: TimeInterval {
        TimeInterval(PosteightStore.trashRetentionDays) * 24 * 60 * 60
    }

    /// Nothing may leave a second early — the window is announced to the user in the trash
    /// window, so it has to be the window they were told about.
    @MainActor
    @Test("Trash surviving right up to the retention window is kept")
    func trashJustInsideWindow() throws {
        let (directory, store, _) = try retentionFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let deletedAt = try #require(store.trashedNotes.first).deletedAt

        store.purgeExpiredTrash(now: deletedAt.addingTimeInterval(retention - 1))
        #expect(store.trashedNotes.count == 1)
        #expect(store.trashedTabs.count == 1)
    }

    @MainActor
    @Test("Trash past the retention window is dropped, notes and tabs alike")
    func trashPastWindow() throws {
        let (directory, store, _) = try retentionFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let deletedAt = try #require(store.trashedNotes.first).deletedAt

        store.purgeExpiredTrash(now: deletedAt.addingTimeInterval(retention + 1))
        #expect(store.trashedNotes.isEmpty)
        #expect(store.trashedTabs.isEmpty)
    }

    /// Expiry has to actually reach disk, or the words are still in `trash.json` after the app
    /// stops showing them.
    @MainActor
    @Test("Expired trash is gone from disk after the launch that purged it")
    func expiredTrashLeavesDisk() throws {
        let (directory, store, _) = try retentionFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.flush()

        let trashURL = directory.appendingPathComponent("trash.json")
        var decoded = try JSONDecoder().decode([TrashedStickyNote].self,
                                               from: try Data(contentsOf: trashURL))
        decoded[0].deletedAt = Date().addingTimeInterval(-retention - 60)
        try JSONEncoder().encode(decoded).write(to: trashURL, options: .atomic)

        let relaunched = PosteightStore(directory: directory)
        #expect(relaunched.trashedNotes.isEmpty)
        relaunched.flush()

        let onDisk = try JSONDecoder().decode([TrashedStickyNote].self,
                                              from: try Data(contentsOf: trashURL))
        #expect(onDisk.isEmpty)
    }
}
