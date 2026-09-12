import AppKit
import SwiftUI

struct PlainEditableTextField: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.editingStore) private var editingStore
    var placeholder: String = ""
    var fontSize: CGFloat = 13
    var fontWeight: NSFont.Weight = .regular
    var fontName: String? = nil
    var textOpacity: CGFloat = 0.78
    /// SwiftUI's `.focused()` does not reach an `NSTextField`, so focus is requested here and
    /// handed to AppKit directly.
    var isFocused = false
    var placesCaretAtEndOnFocus = false
    var onEditingChanged: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onDeleteEmpty: (() -> Bool)?

    func makeNSView(context: Context) -> NSTextField {
        let textField = FocusableTextField()
        textField.delegate = context.coordinator
        textField.isEditable = true
        textField.isSelectable = true
        textField.isEnabled = true
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.sendsActionOnEndEditing = true
        // NSCell configures the shared field editor each time editing starts.
        textField.cell?.allowsUndo = editingStore == nil
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        if let editingStore, context.coordinator.historyRevision != editingStore.historyRevision {
            context.coordinator.historyRevision = editingStore.historyRevision
            if let editor = textField.currentEditor() as? NSTextView {
                let selection = editor.selectedRange()
                editor.string = text
                editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            }
            textField.stringValue = text
        }

        if !context.coordinator.isEditing, textField.stringValue != text {
            textField.stringValue = text
        }

        textField.placeholderString = placeholder
        let font = fontName.flatMap { NSFont(name: $0, size: fontSize) }
            ?? .systemFont(ofSize: fontSize, weight: fontWeight)
        textField.font = font
        if let editor = textField.currentEditor() as? NSTextView, editor.font != font {
            editor.font = font
        }
        textField.textColor = NSColor.black.withAlphaComponent(textOpacity)

        // Only the rising edge moves focus, so a redraw never steals the caret back.
        if isFocused, !context.coordinator.didRequestFocus {
            DispatchQueue.main.async {
                // A row can be built before it joins a window; leaving the flag clear retries then.
                guard let window = textField.window else { return }
                guard context.coordinator.parent.isFocused,
                      !context.coordinator.didRequestFocus else { return }
                context.coordinator.didRequestFocus = true
                if textField.currentEditor() == nil, window.makeFirstResponder(textField),
                   context.coordinator.parent.placesCaretAtEndOnFocus,
                   let editor = textField.currentEditor() as? NSTextView {
                    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                }
            }
        } else if !isFocused {
            context.coordinator.didRequestFocus = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlainEditableTextField
        var isEditing = false
        var didRequestFocus = false
        var historyRevision = 0

        init(parent: PlainEditableTextField) {
            self.parent = parent
        }

        /// Up and down move between checklist rows instead of walking the caret inside one line.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.deleteBackward(_:)):
                // Let AppKit handle text, selections, line breaks and Korean composition.
                guard !textView.hasMarkedText(), textView.string.isEmpty,
                      textView.selectedRange() == NSRange(location: 0, length: 0),
                      let onDeleteEmpty = parent.onDeleteEmpty else { return false }
                return onDeleteEmpty()
            case #selector(NSResponder.moveUp(_:)):
                guard let onMoveUp = parent.onMoveUp else { return false }
                onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                guard let onMoveDown = parent.onMoveDown else { return false }
                onMoveDown()
                return true
            default:
                return false
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            didRequestFocus = true
            parent.onEditingChanged?(true)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            if let editor = textField.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
            // The live editor is the source of truth during editing.
            parent.text = textField.currentEditor()?.string ?? textField.stringValue
            // Keep individual edits undoable without splitting a Korean IME composition.
            if let editor = textField.currentEditor() as? NSTextView, !editor.hasMarkedText() {
                editor.breakUndoCoalescing()
            }
        }

        /// Editing can end *because* SwiftUI is updating — presenting a popover hands key window
        /// to it, which makes this field resign. Writing to the store there publishes a change
        /// mid-update ("Publishing changes from within view updates is not allowed"), so the
        /// write is put one hop later, the same way the window configurator defers its work.
        /// `isEditing` stays set until then, or an `updateNSView` in between would overwrite the
        /// field with the store's stale value and drop the edit.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                isEditing = false
                parent.onEditingChanged?(false)
                return
            }

            parent.editingStore?.endTextUndoGroup()
            let revision = parent.editingStore?.historyRevision
            let value = textField.stringValue
            let submitted = (notification.userInfo?["NSTextMovement"] as? Int) == NSReturnTextMovement

            DispatchQueue.main.async { [self] in
                isEditing = false
                // Undo can run before this deferred callback. Never write a stale value back.
                if revision == parent.editingStore?.historyRevision {
                    parent.text = value
                }
                parent.onEditingChanged?(false)

                if submitted, revision == parent.editingStore?.historyRevision {
                    parent.onSubmit?()
                }
            }
        }
    }
}

private final class FocusableTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
    }
}
