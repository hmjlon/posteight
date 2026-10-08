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
    var showsWholeSelection = false
    var searchFocus: SearchFocusRequest?
    var onSearchFocusApplied: ((UUID) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onDeleteEmpty: (() -> Bool)?
    var onCommandReturn: (() -> Void)?
    /// 붙여넣기를 먼저 받아 본다. 붙여넣을 글과 필드 글자 전체가 선택돼 있는지를 받고, 처리했으면
    /// `true`. `false` 거나 없으면 AppKit 기본대로 붙여넣는다 — 한 줄 필드라 줄바꿈은 공백이 된다.
    var onPaste: ((_ text: String, _ replacesAll: Bool) -> Bool)?

    /// 메모 창의 키 모니터가 ⌘↩ 를 지금 편집 중인 필드로 넘긴다. 필드 편집기의 delegate 가 그 필드다.
    @MainActor static func performCommandReturn(in window: NSWindow?) -> Bool {
        guard let editor = window?.firstResponder as? NSTextView,
              let field = editor.delegate as? NSTextField,
              let coordinator = field.delegate as? Coordinator,
              let action = coordinator.parent.onCommandReturn else { return false }
        finishComposition(in: editor, coordinator: coordinator)
        action()
        return true
    }

    /// 한글을 조합하던 중이면 조합부터 끝낸다. "장보기" 의 "기" 는 다음 키가 올 때까지 조합 중으로
    /// 남는다. ⌘↩ 는 모니터가 삼키고 붙여넣기는 입력기를 거치지 않으니, 입력기는 끝낼 기회를 얻지
    /// 못한다. 그대로 두면 "장보" 로 완료되거나, 붙여넣은 글이 조합 중인 글자를 덮는다. 순서는
    /// Firefox 의 `CommitIMEComposition` 을 따랐다 — 입력기 쪽 조합을 먼저 버리게 하고, 입력기가
    /// 스스로 확정하지 않았으면 필드에서 확정한다.
    @MainActor fileprivate static func finishComposition(in editor: NSTextView, coordinator: Coordinator) {
        guard editor.hasMarkedText() else { return }
        editor.inputContext?.discardMarkedText()
        if editor.hasMarkedText() { editor.unmarkText() }
        coordinator.parent.text = editor.string
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = FocusableTextField()
        textField.delegate = context.coordinator
        textField.onAttached = { [weak coordinator = context.coordinator, weak textField] in
            guard let textField else { return }
            coordinator?.applySearchFocus(to: textField)
        }
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
        // 선택 배경은 창이 key 일 때만 활성 색이다. macOS 는 비활성 선택을 회색으로 낮추고,
        // 여기서 그러지 않으면 뒤로 물러난 메모가 활성 창처럼 파랗게 남는다. 창이 key 를
        // 잃으면 전체 선택 자체가 풀리지만(`StickyNoteWindowView` 의 `didResignKey`),
        // SwiftUI 가 다시 그리기 전에 AppKit 이 먼저 비활성 모습으로 한 번 그린다.
        let isEmphasized = textField.window?.isKeyWindow ?? false
        textField.drawsBackground = showsWholeSelection
        textField.backgroundColor = showsWholeSelection
            ? (isEmphasized ? .selectedTextBackgroundColor : .unemphasizedSelectedTextBackgroundColor)
            : .clear
        textField.textColor = showsWholeSelection
            ? (isEmphasized ? .selectedTextColor : .unemphasizedSelectedTextColor)
            : NSColor.black.withAlphaComponent(textOpacity)

        if searchFocus != nil {
            DispatchQueue.main.async { context.coordinator.applySearchFocus(to: textField) }
            return
        }

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
        var appliedSearchID: UUID?

        @MainActor func applySearchFocus(to textField: NSTextField) {
            guard let request = parent.searchFocus, request.id != appliedSearchID,
                  !AppLock.shared.isLocked, let window = textField.window,
                  let range = request.caret(in: textField.stringValue) else { return }
            window.makeKeyAndOrderFront(nil)
            guard window.makeFirstResponder(textField),
                  let editor = textField.currentEditor() as? NSTextView else { return }
            editor.setSelectedRange(range)
            editor.scrollRangeToVisible(range)
            didRequestFocus = true
            appliedSearchID = request.id
            parent.onSearchFocusApplied?(request.id)
        }

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
    var onAttached: (@MainActor () -> Void)?

    override class var cellClass: AnyClass? {
        get { LinePasteCell.self }
        set { super.cellClass = newValue }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { DispatchQueue.main.async { [weak self] in self?.onAttached?() } }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
    }
}

/// 한 줄 필드는 붙여넣은 줄바꿈을 공백으로 바꾼 뒤에야 텍스트 변경을 알린다 — 그때는 원래 줄을
/// 알 길이 없다. 필드에 `textView(_:shouldChangeTextIn:replacementString:)` 를 달아 봐도 불리지 않았다.
/// 그래서 페이스트보드를 읽는 자리에서 가로챈다. ⌘V, 편집 메뉴, 우클릭, 끌어다 놓기가 모두 여기를
/// 지난다. 필드마다 자기 필드 편집기를 갖는다. 창이 나눠 쓰는 편집기는 갈아 끼울 수 없다.
private final class LinePasteCell: NSTextFieldCell {
    private lazy var editor: LinePasteFieldEditor = {
        let editor = LinePasteFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

private final class LinePasteFieldEditor: NSTextView {
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let text = pboard.string(forType: .string),
              let field = delegate as? NSTextField,
              let coordinator = field.delegate as? PlainEditableTextField.Coordinator,
              let onPaste = coordinator.parent.onPaste
        else { return super.readSelection(from: pboard, type: type) }
        PlainEditableTextField.finishComposition(in: self, coordinator: coordinator)
        let length = (string as NSString).length
        let replacesAll = length > 0 && selectedRange() == NSRange(location: 0, length: length)
        guard onPaste(text, replacesAll) else { return super.readSelection(from: pboard, type: type) }
        // 지금 편집 중인 행이 채워졌으면 그 글을 보여 준다. 편집 중에는 `updateNSView` 가 필드를
        // 덮어쓰지 않고, 스토어 쓰기는 실행 취소 때만 편집기를 다시 읽게 한다.
        let current = coordinator.parent.text
        if string != current {
            string = current
            setSelectedRange(NSRange(location: (current as NSString).length, length: 0))
        }
        return true
    }
}
