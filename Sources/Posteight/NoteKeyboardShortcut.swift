import AppKit

/// Key codes identify the physical shortcut keys even while the Korean IME is active.
enum NoteKeyboardShortcut {
    case addTab, deleteTab, close, undo, redo

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch (event.keyCode, modifiers) {
        case (17, [.command]): self = .addTab
        case (51, [.command]): self = .deleteTab
        case (53, []): self = .close
        case (6, [.command]): self = .undo
        case (6, [.command, .shift]): self = .redo
        default: return nil
        }
    }

}
