import AppKit
import SwiftUI

struct PlainEditableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var fontSize: CGFloat = 13
    var fontWeight: NSFont.Weight = .regular
    var textOpacity: CGFloat = 0.78
    /// SwiftUI's `.focused()` does not reach an `NSTextField`, so focus is requested here and
    /// handed to AppKit directly.
    var isFocused = false
    var onEditingChanged: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

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
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if !context.coordinator.isEditing, textField.stringValue != text {
            textField.stringValue = text
        }

        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: fontSize, weight: fontWeight)
        textField.textColor = NSColor.black.withAlphaComponent(textOpacity)

        // Only the rising edge moves focus, so a redraw never steals the caret back.
        if isFocused, !context.coordinator.didRequestFocus {
            DispatchQueue.main.async {
                // A row can be built before it joins a window; leaving the flag clear retries then.
                guard let window = textField.window else { return }
                context.coordinator.didRequestFocus = true
                window.makeFirstResponder(textField)
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

        init(parent: PlainEditableTextField) {
            self.parent = parent
        }

        /// Up and down move between checklist rows instead of walking the caret inside one line.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
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
            parent.onEditingChanged?(true)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
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

            let value = textField.stringValue
            let submitted = (notification.userInfo?["NSTextMovement"] as? Int) == NSReturnTextMovement

            DispatchQueue.main.async { [self] in
                isEditing = false
                parent.text = value
                parent.onEditingChanged?(false)

                if submitted {
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
