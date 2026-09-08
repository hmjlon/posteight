import AppKit
import SwiftUI
import Testing
@testable import Posteight

@Suite(.serialized)
@MainActor
struct PlainTextUndoTests {
    @Test func undoAcrossLiveFieldsUpdatesBothEditorsAndRejectsDeferredStaleWrites() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let noteID = store.addNote()
        let tab = try #require(store.notes.first { $0.id == noteID }?.selectedTab)
        let firstID = try #require(tab.items.first?.id)
        let secondID = try #require(store.addItem(to: noteID, tabID: tab.id))
        store.clearEditingHistory()
        let host = NSHostingView(rootView: HistoryFields(store: store, noteID: noteID, tabID: tab.id))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let fields = findFields(in: host)
        #expect(fields.count == 2)
        let first = try #require(fields.first)
        let second = try #require(fields.last)
        #expect(first.cell?.allowsUndo == false)
        window.makeFirstResponder(first)
        let editor = try #require(first.currentEditor() as? NSTextView)
        editor.insertText("1", replacementRange: NSRange(location: 0, length: 0))
        window.makeFirstResponder(second)
        try await Task.sleep(for: .milliseconds(30))
        let secondEditor = try #require(second.currentEditor() as? NSTextView)
        secondEditor.insertText("2", replacementRange: NSRange(location: 0, length: 0))
        #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: firstID) == "1")
        #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: secondID) == "2")
        #expect(store.undo())
        try await Task.sleep(for: .milliseconds(30))
        #expect(secondEditor.string == "")
        #expect(store.undo())
        try await Task.sleep(for: .milliseconds(30))
        #expect(first.stringValue == "")
        #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: firstID) == "")
        #expect(store.redo())
        #expect(store.redo())
        try await Task.sleep(for: .milliseconds(30))
        #expect(secondEditor.string == "2")
        // Ending an edit schedules a write; undo must win even before that write runs.
        window.makeFirstResponder(nil)
        #expect(store.undo())
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: secondID) == "")
    }

    private func findFields(in view: NSView) -> [NSTextField] {
        if let field = view as? NSTextField { return [field] }
        return view.subviews.flatMap { findFields(in: $0) }
    }
}

private struct HistoryFields: View {
    @ObservedObject var store: PosteightStore
    let noteID: UUID
    let tabID: UUID

    var body: some View {
        VStack {
            ForEach(store.notes.first { $0.id == noteID }?.selectedTab?.items ?? []) { item in
                PlainEditableTextField(text: Binding(
                    get: { store.itemTitle(noteID: noteID, tabID: tabID, itemID: item.id) ?? "" },
                    set: { store.updateItemTitle(noteID: noteID, tabID: tabID, itemID: item.id, title: $0) }
                ))
            }
        }
        .environment(\.editingStore, store)
    }
}
