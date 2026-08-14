import Foundation
import Testing

@testable import Posteight

/// Notes are the only thing the app cannot regenerate, so the save path gets its own
/// round trip. Each store points at a throwaway directory, never the real one.
@Suite("Persistence", .serialized)
@MainActor
struct PersistenceTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("posteight-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Flushing writes notes that a fresh store reads back")
    func roundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        store.updateNoteTitle(noteID, title: "저장 확인")
        store.flush()

        let reloaded = PosteightStore(directory: directory)
        #expect(reloaded.notes.contains { $0.id == noteID && $0.title == "저장 확인" })
        #expect(reloaded.notes.count == store.notes.count)
    }

    @Test("Trashed notes survive a reload too")
    func trashRoundTrip() throws {
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
        store.updateNoteTitle(noteID, title: "디바운스")

        try await Task.sleep(for: .seconds(1))

        let reloaded = PosteightStore(directory: directory)
        #expect(reloaded.notes.contains { $0.id == noteID && $0.title == "디바운스" })
    }
}
