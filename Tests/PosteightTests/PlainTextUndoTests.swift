import AppKit
import SwiftUI
import Testing
@testable import Posteight

extension AppKitEditingTests {
    @Suite
    @MainActor
    struct PlainTextUndoTests {
        @Test func emptyRowDeletionFocusesPreviousEndWithoutDeletingItsText() async throws {
            _ = NSApplication.shared
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = PosteightStore(directory: directory)
            let noteID = store.addNote()
            let tab = try #require(store.notes.first { $0.id == noteID }?.selectedTab)
            let firstID = try #require(tab.items.first?.id)
            store.updateItemTitle(noteID: noteID, tabID: tab.id, itemID: firstID, title: "윗줄🙂")
            let secondID = try #require(store.addItem(to: noteID, tabID: tab.id))
            let host = NSHostingView(rootView: HistoryFields(store: store, noteID: noteID, tabID: tab.id))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer {
                window.makeFirstResponder(nil)
                window.orderOut(nil)
                window.contentView = nil
            }
            host.layoutSubtreeIfNeeded()
            let fieldsReady = try await waitForEditorState { findFields(in: host).count == 2 }
            try #require(fieldsReady)
            let fields = findFields(in: host)
            let first = try #require(fields.first)
            let second = try #require(fields.last)
            // Reproduce mouse focus after the previous row was already focused.
            window.makeFirstResponder(first)
            let firstReady = try await waitForEditorState { first.currentEditor() != nil }
            try #require(firstReady)
            window.makeFirstResponder(second)
            let secondReady = try await waitForEditorState { second.currentEditor() != nil }
            try #require(secondReady)
            let editor = try #require(second.currentEditor() as? NSTextView)
            editor.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            let previousReady = try await waitForEditorState {
                guard let editor = first.currentEditor() as? NSTextView else { return false }
                return store.itemTitle(noteID: noteID, tabID: tab.id, itemID: secondID) == nil
                    && editor.selectedRange() == NSRange(location: ("윗줄🙂" as NSString).length, length: 0)
            }
            try #require(previousReady)
            #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: secondID) == nil)
            let previousEditor = try #require(first.currentEditor() as? NSTextView)
            #expect(previousEditor.string == "윗줄🙂")
            #expect(previousEditor.selectedRange() == NSRange(location: ("윗줄🙂" as NSString).length, length: 0))
            previousEditor.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: firstID) == "윗줄")
        }

        @Test func backspaceOnlyInterceptsEmptyUnmarkedEditor() {
            var calls = 0
            let field = PlainEditableTextField(text: .constant(""), onDeleteEmpty: {
                calls += 1
                return true
            })
            let coordinator = field.makeCoordinator()
            let control = NSTextField()
            let editor = NSTextView()
            let command = #selector(NSResponder.deleteBackward(_:))
            for value in ["글자", " ", "첫 줄\n둘째 줄", "\n"] {
                editor.string = value
                editor.setSelectedRange(NSRange(location: 0, length: 0))
                #expect(!coordinator.control(control, textView: editor, doCommandBy: command))
            }
            editor.string = ""
            editor.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0),
                                 replacementRange: NSRange(location: 0, length: 0))
            #expect(!coordinator.control(control, textView: editor, doCommandBy: command))
            #expect(calls == 0)
            editor.unmarkText()
            editor.string = ""
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            #expect(coordinator.control(control, textView: editor, doCommandBy: command))
            #expect(calls == 1)
        }

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
            defer {
                window.makeFirstResponder(nil)
                window.orderOut(nil)
                window.contentView = nil
            }
            host.layoutSubtreeIfNeeded()
            let fieldsReady = try await waitForEditorState { findFields(in: host).count == 2 }
            try #require(fieldsReady)
            let fields = findFields(in: host)
            #expect(fields.count == 2)
            let first = try #require(fields.first)
            let second = try #require(fields.last)
            #expect(first.cell?.allowsUndo == false)
            window.makeFirstResponder(first)
            let editor = try #require(first.currentEditor() as? NSTextView)
            editor.insertText("1", replacementRange: NSRange(location: 0, length: 0))
            window.makeFirstResponder(second)
            let secondReady = try await waitForEditorState { second.currentEditor() != nil }
            try #require(secondReady)
            let secondEditor = try #require(second.currentEditor() as? NSTextView)
            secondEditor.insertText("2", replacementRange: NSRange(location: 0, length: 0))
            #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: firstID) == "1")
            #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: secondID) == "2")
            #expect(store.undo())
            let secondUndone = try await waitForEditorState { secondEditor.string == "" }
            try #require(secondUndone)
            #expect(secondEditor.string == "")
            #expect(store.undo())
            let firstUndone = try await waitForEditorState { first.stringValue == "" }
            try #require(firstUndone)
            #expect(first.stringValue == "")
            #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: firstID) == "")
            #expect(store.redo())
            #expect(store.redo())
            let redone = try await waitForEditorState { secondEditor.string == "2" }
            try #require(redone)
            #expect(secondEditor.string == "2")
            // Ending an edit schedules a write; undo must win even before that write runs.
            window.makeFirstResponder(nil)
            #expect(store.undo())
            let ended = try await waitForEditorState {
                let coordinator = second.delegate as? PlainEditableTextField.Coordinator
                return coordinator?.isEditing == false
            }
            try #require(ended)
            #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: secondID) == "")
        }

        @Test func commandReturnFinishesCompositionThenTogglesTheEditedRow() async throws {
            _ = NSApplication.shared
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = PosteightStore(directory: directory)
            let noteID = store.addNote()
            let tab = try #require(store.notes.first { $0.id == noteID }?.selectedTab)
            let itemID = try #require(tab.items.first?.id)
            func isDone() -> Bool? {
                store.notes.first { $0.id == noteID }?.selectedTab?.items.first { $0.id == itemID }?.isDone
            }
            let host = NSHostingView(rootView: HistoryFields(store: store, noteID: noteID, tabID: tab.id))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer {
                window.makeFirstResponder(nil)
                window.orderOut(nil)
                window.contentView = nil
            }
            host.layoutSubtreeIfNeeded()
            let fieldReady = try await waitForEditorState { findFields(in: host).count == 1 }
            try #require(fieldReady)
            let field = try #require(findFields(in: host).first)

            // 아무것도 편집하지 않을 때는 키를 그대로 흘려보낸다.
            #expect(!PlainEditableTextField.performCommandReturn(in: window))

            window.makeFirstResponder(field)
            let editing = try await waitForEditorState { field.currentEditor() != nil }
            try #require(editing)
            let editor = try #require(field.currentEditor() as? NSTextView)
            editor.insertText("장보", replacementRange: NSRange(location: NSNotFound, length: 0))
            editor.setMarkedText("기", selectedRange: NSRange(location: 1, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: itemID) == "장보")

            #expect(PlainEditableTextField.performCommandReturn(in: window))
            #expect(!editor.hasMarkedText())
            #expect(store.itemTitle(noteID: noteID, tabID: tab.id, itemID: itemID) == "장보기")
            #expect(isDone() == true)
            // 커서는 그 행에 남는다.
            #expect(window.firstResponder === editor)

            #expect(PlainEditableTextField.performCommandReturn(in: window))
            #expect(isDone() == false)
        }

        @Test func pastingSeveralLinesSplitsThemIntoRows() async throws {
            _ = NSApplication.shared
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = PosteightStore(directory: directory)
            let noteID = store.addNote()
            let tab = try #require(store.notes.first { $0.id == noteID }?.selectedTab)
            func titles() -> [String] {
                store.notes.first { $0.id == noteID }?.selectedTab?.items.map(\.title) ?? []
            }
            let host = NSHostingView(rootView: HistoryFields(store: store, noteID: noteID, tabID: tab.id))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            // 사용자의 클립보드를 건드리지 않는다.
            let pasteboard = NSPasteboard(name: .init("posteight-tests-\(UUID().uuidString)"))
            defer {
                pasteboard.releaseGlobally()
                window.makeFirstResponder(nil)
                window.orderOut(nil)
                window.contentView = nil
            }
            host.layoutSubtreeIfNeeded()
            let fieldReady = try await waitForEditorState { findFields(in: host).count == 1 }
            try #require(fieldReady)
            let field = try #require(findFields(in: host).first)
            window.makeFirstResponder(field)
            let editing = try await waitForEditorState { field.currentEditor() != nil }
            try #require(editing)
            let editor = try #require(field.currentEditor() as? NSTextView)

            pasteboard.clearContents()
            pasteboard.setString("- [ ] 장보기\n- [x] 메일 답장", forType: .string)
            #expect(editor.readSelection(from: pasteboard))
            #expect(titles() == ["장보기", "메일 답장"])
            // 편집 중이던 행은 채워진 글을 바로 보여 준다.
            #expect(editor.string == "장보기")

            // 커서는 마지막으로 들어간 행으로 간다.
            let moved = try await waitForEditorState {
                findFields(in: host).count == 2 && findFields(in: host).last?.currentEditor() != nil
            }
            try #require(moved)

            // 한 줄짜리 붙여넣기는 그대로다.
            let lastEditor = try #require(findFields(in: host).last?.currentEditor() as? NSTextView)
            pasteboard.clearContents()
            pasteboard.setString(" 답장", forType: .string)
            #expect(lastEditor.readSelection(from: pasteboard))
            #expect(titles() == ["장보기", "메일 답장 답장"])
        }

        @Test func pastingFinishesCompositionAndReplacesASelectedRow() async throws {
            _ = NSApplication.shared
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = PosteightStore(directory: directory)
            let noteID = store.addNote()
            let tab = try #require(store.notes.first { $0.id == noteID }?.selectedTab)
            func items() -> [TodoItem] { store.notes.first { $0.id == noteID }?.selectedTab?.items ?? [] }
            let host = NSHostingView(rootView: HistoryFields(store: store, noteID: noteID, tabID: tab.id))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            let pasteboard = NSPasteboard(name: .init("posteight-tests-\(UUID().uuidString)"))
            defer {
                pasteboard.releaseGlobally()
                window.makeFirstResponder(nil)
                window.orderOut(nil)
                window.contentView = nil
            }
            host.layoutSubtreeIfNeeded()
            let fieldReady = try await waitForEditorState { findFields(in: host).count == 1 }
            try #require(fieldReady)
            let field = try #require(findFields(in: host).first)
            window.makeFirstResponder(field)
            let editing = try await waitForEditorState { field.currentEditor() != nil }
            try #require(editing)
            let editor = try #require(field.currentEditor() as? NSTextView)

            // "ㅎ" 을 조합하던 중에 붙여넣어도 그 글자는 남는다. 행에 글이 생겼으니 목록은 아래로 간다.
            editor.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            pasteboard.clearContents()
            pasteboard.setString("하나\n둘", forType: .string)
            #expect(editor.readSelection(from: pasteboard))
            #expect(!editor.hasMarkedText())
            #expect(items().map(\.title) == ["ㅎ", "하나", "둘"])

            let moved = try await waitForEditorState {
                findFields(in: host).count == 3 && findFields(in: host).last?.currentEditor() != nil
            }
            try #require(moved)

            // 행 글자를 전부 고른 채 표시 붙은 한 줄을 붙이면 그 행이 바뀐다.
            let lastEditor = try #require(findFields(in: host).last?.currentEditor() as? NSTextView)
            lastEditor.selectAll(nil)
            pasteboard.clearContents()
            pasteboard.setString("- [x] 셋", forType: .string)
            #expect(lastEditor.readSelection(from: pasteboard))
            #expect(items().map(\.title) == ["ㅎ", "하나", "셋"])
            #expect(items().last?.isDone == true)
            #expect(lastEditor.string == "셋")
        }

        private func findFields(in view: NSView) -> [NSTextField] {
            if let field = view as? NSTextField { return [field] }
            return view.subviews.flatMap { findFields(in: $0) }
        }
    }

}

private struct HistoryFields: View {
    @ObservedObject var store: PosteightStore
    @State private var focusedItemID: UUID?
    let noteID: UUID
    let tabID: UUID

    var body: some View {
        VStack {
            ForEach(store.notes.first { $0.id == noteID }?.selectedTab?.items ?? []) { item in
                PlainEditableTextField(text: Binding(
                    get: { store.itemTitle(noteID: noteID, tabID: tabID, itemID: item.id) ?? "" },
                    set: { store.updateItemTitle(noteID: noteID, tabID: tabID, itemID: item.id, title: $0) }
                ), isFocused: focusedItemID == item.id, placesCaretAtEndOnFocus: true,
                onEditingChanged: { if $0 { focusedItemID = item.id } },
                onDeleteEmpty: {
                    guard let previous = store.deleteEmptyItemBackward(
                        noteID: noteID, tabID: tabID, itemID: item.id
                    ) else { return false }
                    focusedItemID = previous
                    return true
                }, onCommandReturn: {
                    store.toggleItem(noteID: noteID, tabID: tabID, itemID: item.id)
                }, onPaste: { text, replacesAll in
                    let last = store.pasteItems(text, noteID: noteID, tabID: tabID, at: item.id,
                                                replacingCurrent: replacesAll)
                    if let last { focusedItemID = last }
                    return last != nil || text.contains(where: \.isNewline)
                })
            }
        }
        .environment(\.editingStore, store)
    }
}
