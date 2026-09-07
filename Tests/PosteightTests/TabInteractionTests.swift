import Foundation
import Testing
@testable import Posteight

@Suite("Tab merging and quick delete", .serialized)
@MainActor
struct TabInteractionTests {
    @Test("Merging preserves every tab, selection and contents after reload")
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
    }

    @Test("Invalid merges and more than five tabs leave both notes untouched")
    func invalidMerge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let target = store.addNote()
        let source = store.addNote()
        for _ in 0..<4 { store.addTab(to: target) }
        let before = store.notes
        #expect(!store.mergeNotes(from: source, into: target))
        #expect(!store.mergeNotes(from: source, into: source))
        #expect(!store.mergeNotes(from: UUID(), into: target))
        #expect(store.notes == before)
    }

    @Test("Quick delete trashes only the selection, and the final tab trashes its note")
    func quickDelete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let id = store.addNote()
        let added = try #require(store.addTab(to: id))
        store.trashSelectedTab(in: id)
        #expect(store.notes.first { $0.id == id }?.tabs.count == 1)
        #expect(store.trashedTabs.contains { $0.id == added })
        store.trashSelectedTab(in: id)
        let reloaded = PosteightStore(directory: directory)
        #expect(!reloaded.notes.contains { $0.id == id })
        #expect(reloaded.trashedNotes.contains { $0.id == id })
        reloaded.restoreNote(id)
        reloaded.restoreTab(added)
        #expect(reloaded.notes.first { $0.id == id }?.tabs.count == 2)
    }

}
