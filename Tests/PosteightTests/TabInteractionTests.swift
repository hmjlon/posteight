import Foundation
import Testing
@testable import Posteight

@Suite("Tab merging and quick delete", .serialized)
@MainActor
struct TabInteractionTests {
    @Test("The tab bar collapses before equal division makes a tab unselectable")
    func tabsCollapseBeforeTheyGetTooNarrow() {
        func strip(_ noteWidth: CGFloat) -> CGFloat {
            noteWidth - MemoSurfaceMetrics.trailingControlsWidth - MemoSurfaceMetrics.addTabButtonWidth
        }
        // 기본 폭에 탭 10개는 22pt, 최대 폭에서도 34pt — 앞의 것은 접어야 한다.
        #expect(MemoSurfaceMetrics.collapsesTabs(count: 10, stripWidth: strip(310), isAtMinimumWidth: false))
        #expect(!MemoSurfaceMetrics.collapsesTabs(count: 10, stripWidth: strip(430), isAtMinimumWidth: false))
        // v0.1.0 에서 나올 수 있던 가장 좁은 배치 — 최소 폭 바로 위에 탭 5개, 31.8pt — 는 그대로 편다.
        #expect(!MemoSurfaceMetrics.collapsesTabs(count: 5, stripWidth: strip(245), isAtMinimumWidth: false))
        #expect(MemoSurfaceMetrics.collapsesTabs(count: 2, stripWidth: strip(244), isAtMinimumWidth: true))
        #expect(!MemoSurfaceMetrics.collapsesTabs(count: 1, stripWidth: strip(244), isAtMinimumWidth: true))
    }

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

    @Test("Invalid merges and more than ten tabs leave both notes untouched")
    func invalidMerge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let target = store.addNote()
        let source = store.addNote()
        for _ in 1..<10 { store.addTab(to: target) }
        let before = store.notes
        #expect(!store.mergeNotes(from: source, into: target))
        #expect(!store.mergeNotes(from: source, into: source))
        #expect(!store.mergeNotes(from: UUID(), into: target))
        #expect(store.notes == before)
    }

    @Test("Ten tabs survive reload and an eleventh is rejected")
    func tenTabLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let id = store.addNote()
        for _ in 1..<10 {
            _ = try #require(store.addTab(to: id))
        }
        let before = store.notes
        #expect(store.notes.first { $0.id == id }?.tabs.count == 10)
        #expect(store.addTab(to: id) == nil)
        #expect(store.notes == before)
        store.flush()
        let reloaded = PosteightStore(directory: directory)
        #expect(reloaded.notes.first { $0.id == id }?.tabs.count == 10)
    }

    @Test("Merging into exactly ten tabs succeeds")
    func mergeAtLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let target = store.addNote()
        let source = store.addNote()
        for _ in 1..<9 { store.addTab(to: target) }
        #expect(store.mergeNotes(from: source, into: target))
        #expect(store.notes.first { $0.id == target }?.tabs.count == 10)
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
