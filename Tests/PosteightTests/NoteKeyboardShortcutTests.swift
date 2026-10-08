import AppKit
import Testing
@testable import Posteight

struct NoteKeyboardShortcutTests {
    @Test func shortcutsWorkWithKoreanInput() throws {
        let tab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "ㅅ", charactersIgnoringModifiers: "ㅅ", isARepeat: false, keyCode: 17))
        #expect(NoteKeyboardShortcut(event: tab) == .addTab)
        let copyAll = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "ㅁ", charactersIgnoringModifiers: "ㅁ", isARepeat: false, keyCode: 0))
        #expect(NoteKeyboardShortcut(event: copyAll) == .selectAll)
        let copy = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "ㅊ", charactersIgnoringModifiers: "ㅊ", isARepeat: false, keyCode: 8))
        #expect(NoteKeyboardShortcut(event: copy) == .copy)
        let undo = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "ㅋ", charactersIgnoringModifiers: "ㅋ", isARepeat: false, keyCode: 6))
        #expect(NoteKeyboardShortcut(event: undo) == .undo)
        let toggle = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        #expect(NoteKeyboardShortcut(event: toggle) == .toggleDone)
        // 숫자 키패드의 Enter. 키패드 키에는 `.numericPad` 가 붙어 온다.
        let keypadToggle = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .numericPad], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{3}", charactersIgnoringModifiers: "\u{3}", isARepeat: false, keyCode: 76))
        #expect(NoteKeyboardShortcut(event: keypadToggle) == .toggleDone)
    }

    /// 그냥 Return 은 다음 행을 만드는 키다. 완료 토글이 가로채면 안 된다.
    @Test func plainReturnIsNotToggleDone() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        #expect(NoteKeyboardShortcut(event: event) == nil)
    }

    @Test func ordinaryTypingDoesNotTriggerShortcuts() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17))
        #expect(NoteKeyboardShortcut(event: event) == nil)
    }
}
