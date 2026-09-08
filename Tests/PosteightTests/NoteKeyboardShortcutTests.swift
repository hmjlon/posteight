import AppKit
import Testing
@testable import Posteight

struct NoteKeyboardShortcutTests {
    @Test func shortcutsWorkWithKoreanInput() throws {
        let tab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "ㅅ", charactersIgnoringModifiers: "ㅅ", isARepeat: false, keyCode: 17))
        #expect(NoteKeyboardShortcut(event: tab) == .addTab)
        let undo = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "ㅋ", charactersIgnoringModifiers: "ㅋ", isARepeat: false, keyCode: 6))
        #expect(NoteKeyboardShortcut(event: undo) == .undo)
    }

    @Test func ordinaryTypingDoesNotTriggerShortcuts() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17))
        #expect(NoteKeyboardShortcut(event: event) == nil)
    }
}
