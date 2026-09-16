import AppKit
import SwiftUI
import Testing
@testable import Posteight

@Suite(.serialized)
@MainActor
struct SearchFocusTests {
    @Test func destinationsAndUTF16Caret() throws {
        let item = TodoItem(title: "🙂 회의 준비", detail: "이전 회의 기록")
        let tab = MemoTab(name: "회의", title: "회의 제목", items: [item])
        let result = NoteSearchResult(noteID: UUID(), tab: tab, matchingItems: [item], matchesHeading: true)
        let hits = result.hits(query: "회의")
        #expect(hits.map(\.id.target) == [.tabName, .tabTitle, .itemTitle(item.id), .itemDetail(item.id)])
        #expect(Set(hits.map(\.id)).count == 4)
        let request = SearchFocusRequest(noteID: result.noteID, tabID: tab.id,
                                         target: .itemTitle(item.id), query: "회의")
        #expect(request.caret(in: item.title) == NSRange(location: 5, length: 0))
        #expect(request.caret(in: "일정 변경") == nil)
    }

    @Test func searchScrollsToRowAndFocusesAgainThenOpensDetail() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let initialTab = try #require(store.notes.first { $0.id == noteID }?.selectedTab)
        for index in 0..<45 {
            let id = try #require(store.addItem(to: noteID, tabID: initialTab.id))
            store.updateItemTitle(noteID: noteID, tabID: initialTab.id, itemID: id, title: "항목 \(index)")
        }
        let note = try #require(store.notes.first { $0.id == noteID })
        let tab = try #require(note.selectedTab)
        let item = try #require(tab.items.last)
        store.updateItemTitle(noteID: noteID, tabID: tab.id, itemID: item.id, title: "🙂 회의 준비")
        store.updateItemDetail(noteID: noteID, tabID: tab.id, itemID: item.id, detail: "지난 회의 기록")
        let host = NSHostingView(rootView: SearchTestNote(store: store, noteID: noteID))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        for _ in 0..<2 {
            store.searchFocusRequest = SearchFocusRequest(noteID: noteID, tabID: tab.id,
                                                          target: .itemTitle(item.id), query: "회의")
            try await Task.sleep(for: .milliseconds(250))
            let field = try #require(fields(in: host).first { $0.stringValue == "🙂 회의 준비" })
            let editor = try #require(field.currentEditor() as? NSTextView)
            #expect(editor.selectedRange() == NSRange(location: 5, length: 0))
            #expect(store.searchFocusRequest == nil)
            var ancestor = field.superview
            while let view = ancestor {
                if let clip = view as? NSClipView {
                    #expect(clip.bounds.intersects(field.convert(field.bounds, to: clip)))
                    break
                }
                ancestor = view.superview
            }
            editor.setSelectedRange(NSRange(location: 0, length: 0))
        }
        store.searchFocusRequest = SearchFocusRequest(noteID: noteID, tabID: tab.id,
                                                      target: .itemDetail(item.id), query: "회의")
        try await Task.sleep(for: .milliseconds(500))
        #expect(store.presentedDetailItemID == item.id)
        #expect(store.searchFocusRequest == nil)
        let detail = try #require(NSApp.windows.compactMap { $0.firstResponder as? NSTextView }
            .first { $0.string == "지난 회의 기록" })
        #expect(detail.selectedRange() == NSRange(location: 5, length: 0))
        store.presentedDetailItemID = nil
    }

    private func fields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
    }
}

private struct SearchTestNote: View {
    @ObservedObject var store: PosteightStore
    let noteID: UUID
    var body: some View {
        if let note = store.notes.first(where: { $0.id == noteID }), let tab = note.selectedTab {
            StickyNoteView(note: note, tab: tab, onResizeChanged: { _ in }, onResizeEnded: { _ in },
                           onDelete: {}, isAllContentSelected: false, isPencilCaseOpen: .constant(false))
                .environmentObject(store)
        }
    }
}
