import AppKit

/// Key codes identify the physical shortcut keys even while the Korean IME is active.
enum NoteKeyboardShortcut {
    case addTab, deleteTab, selectAll, copy, close, undo, redo, toggleDone

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch (event.keyCode, modifiers) {
        case (0, [.command]): self = .selectAll
        case (8, [.command]): self = .copy
        case (17, [.command]): self = .addTab
        case (51, [.command]): self = .deleteTab
        case (53, []): self = .close
        case (6, [.command]): self = .undo
        case (6, [.command, .shift]): self = .redo
        // Return 과 숫자 키패드의 Enter(fn-Return 도 이것이다).
        case (36, [.command]), (76, [.command]): self = .toggleDone
        default: return nil
        }
    }

}
