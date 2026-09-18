import Foundation
import Testing
@testable import Posteight

@Suite("Storage recovery", .serialized)
@MainActor
struct StorageRecoveryTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("posteight-recovery-\(UUID())")
    }

    @Test("Unreadable JSON is preserved, including on termination flush")
    func corruptNotes() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("notes.json")
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: file)
        let store = PosteightStore(directory: root)
        #expect(store.isStorageBlocked)
        #expect(store.storageError == .read)
        #expect(store.notes.isEmpty)
        store.flush()
        #expect(try Data(contentsOf: file) == corrupt)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("trash.json").path))
    }

    @Test("A corrupt trash file blocks all writes, not only trash writes")
    func corruptTrash() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = PosteightStore(directory: root)
        original.flush()
        let notes = try Data(contentsOf: root.appendingPathComponent("notes.json"))
        let corrupt = Data("[".utf8)
        try corrupt.write(to: root.appendingPathComponent("trashed-tabs.json"))
        let loaded = PosteightStore(directory: root)
        #expect(loaded.isStorageBlocked)
        loaded.flush()
        #expect(try Data(contentsOf: root.appendingPathComponent("notes.json")) == notes)
        #expect(try Data(contentsOf: root.appendingPathComponent("trashed-tabs.json")) == corrupt)
    }

    @Test("Failed migration remains retryable after the app loads and flushes")
    func failedMigrationThenRetry() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("legacy")
        let destination = root.appendingPathComponent("container")
        let old = PosteightStore(directory: legacy)
        let id = old.addNote()
        old.flush()
        let trash = legacy.appendingPathComponent("trash.json")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: trash.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: trash.path) }
        let store = PosteightStore(directory: destination, legacyDirectory: legacy)
        #expect(store.storageError == .migration)
        #expect(store.isStorageBlocked)
        store.flush()
        for name in PosteightStore.migratedItems {
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent(name).path))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: trash.path)
        store.retryLoading()
        #expect(!store.isStorageBlocked)
        #expect(store.notes.contains { $0.id == id })
        store.flush()
        #expect(PosteightStore(directory: destination).notes.contains { $0.id == id })
    }

    @Test("Interrupted migration marker takes precedence over partially copied data")
    func interruptedMigration() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PosteightStore(directory: root)
        store.flush()
        try Data().write(to: root.appendingPathComponent(PosteightStore.migrationMarker))
        let blocked = PosteightStore(directory: root, legacyDirectory: root.appendingPathComponent("legacy"))
        #expect(blocked.storageError == .migration)
        #expect(blocked.isStorageBlocked)
    }

    @Test("Save errors are visible and retry keeps edits in memory")
    func failedSave() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PosteightStore(directory: root)
        let id = store.addNote()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("notes.json")
        // A directory at a file destination reliably fails even when tests run privileged.
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        store.flush()
        #expect(store.storageError == .save)
        #expect(store.notes.contains { $0.id == id })
        try FileManager.default.removeItem(at: file)
        store.flush()
        #expect(store.storageError == nil)
        #expect(PosteightStore(directory: root).notes.contains { $0.id == id })
    }

    @Test("Automatic backup preserves the previous session, even after repeated flushes")
    func automaticBackup() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = PosteightStore(directory: root)
        let id = original.addNote()
        original.flush()
        let next = PosteightStore(directory: root)
        next.moveNoteToTrash(id)
        next.flush()
        next.flush()
        #expect(next.backupDate != nil)
        try next.restoreBackup()
        #expect(next.notes.contains { $0.id == id })
        #expect(!next.trashedNotes.contains { $0.id == id })
        #expect(!next.canUndo)
    }

    @Test("Restore recovers corrupt live data and archives the exact original bytes")
    func restoreCorruptStore() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = PosteightStore(directory: root)
        let id = original.addNote()
        original.flush()
        try original.createBackup()
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: root.appendingPathComponent("notes.json"))
        let broken = PosteightStore(directory: root)
        #expect(broken.isStorageBlocked)
        try broken.restoreBackup()
        #expect(!broken.isStorageBlocked)
        #expect(broken.notes.contains { $0.id == id })
        let archive = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("BeforeRestore-") })
        #expect(try Data(contentsOf: archive.appendingPathComponent("notes.json")) == corrupt)
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("backup.json").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("Invalid backup never changes current data")
    func invalidBackup() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PosteightStore(directory: root)
        store.flush()
        let original = try Data(contentsOf: root.appendingPathComponent("notes.json"))
        var snapshot = StoreBackup(notes: store.notes, trashedNotes: [], trashedTabs: [])
        snapshot.formatVersion = 99
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("backup.json"))
        #expect(throws: StorageFailure.self) { try store.restoreBackup() }
        #expect(try Data(contentsOf: root.appendingPathComponent("notes.json")) == original)
    }
    @Test("Interrupted restore completes all collections before loading")
    func interruptedRestore() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = PosteightStore(directory: root)
        let id = original.addNote()
        original.flush()
        let snapshot = StoreBackup(notes: original.notes, trashedNotes: [], trashedTabs: [])
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("pending-restore.json"))
        try Data("broken".utf8).write(to: root.appendingPathComponent("notes.json"))
        let loaded = PosteightStore(directory: root)
        #expect(!loaded.isStorageBlocked)
        #expect(loaded.notes.contains { $0.id == id })
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("pending-restore.json").path))
        loaded.flush()
    }

    @Test("A failed restore remains resumable rather than exposing partially restored data")
    func failedRestoreRetry() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PosteightStore(directory: root)
        let id = store.addNote()
        store.flush()
        try store.createBackup()
        store.moveNoteToTrash(id)
        let trash = root.appendingPathComponent("trash.json")
        try FileManager.default.removeItem(at: trash)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try store.restoreBackup() }
        #expect(store.isStorageBlocked)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("pending-restore.json").path))
        try FileManager.default.removeItem(at: trash)
        store.retryLoading()
        #expect(!store.isStorageBlocked)
        #expect(store.notes.contains { $0.id == id })
        #expect(!store.trashedNotes.contains { $0.id == id })
        store.flush()
    }

    @Test("Manual backup is not immediately overwritten by the session backup")
    func manualBackup() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = PosteightStore(directory: root)
        original.flush()
        let store = PosteightStore(directory: root)
        let id = store.addNote()
        try store.createBackup()
        store.flush()
        store.moveNoteToTrash(id)
        try store.restoreBackup()
        #expect(store.notes.contains { $0.id == id })
    }

    @Test("A new installation with no legacy folder can save normally")
    func noLegacyFolder() {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PosteightStore(directory: root.appendingPathComponent("container"),
                                  legacyDirectory: root.appendingPathComponent("missing"))
        #expect(!store.isStorageBlocked)
        store.flush()
        #expect(store.storageError == nil)
    }

    @Test("Interrupted migration preserves partial bytes and retries from the original")
    func resumeMigration() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("legacy")
        let destination = root.appendingPathComponent("container")
        let original = PosteightStore(directory: legacy)
        let id = original.addNote()
        original.flush()
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let partial = Data("incomplete copy".utf8)
        try partial.write(to: destination.appendingPathComponent("notes.json"))
        try Data().write(to: destination.appendingPathComponent(PosteightStore.migrationMarker))
        let store = PosteightStore(directory: destination, legacyDirectory: legacy)
        #expect(!store.isStorageBlocked)
        #expect(store.notes.contains { $0.id == id })
        let archive = try #require(FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("InterruptedMigration-") })
        #expect(try Data(contentsOf: archive.appendingPathComponent("notes.json")) == partial)
        store.flush()
    }

}
