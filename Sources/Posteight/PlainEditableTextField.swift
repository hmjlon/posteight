import AppKit
import SwiftUI

struct PlainEditableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var fontSize: CGFloat = 13
    var fontWeight: NSFont.Weight = .regular
    var textOpacity: CGFloat = 0.78
    var onEditingChanged: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?

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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlainEditableTextField
        var isEditing = false

        init(parent: PlainEditableTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            parent.onEditingChanged?(true)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            parent.onEditingChanged?(false)
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue

            let movement = notification.userInfo?["NSTextMovement"] as? Int
            if movement == NSReturnTextMovement {
                parent.onSubmit?()
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
