import AppKit
import SwiftUI

struct TodoItemRow: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var fonts = NoteFontLibrary.shared
    @ObservedObject private var settings = AppSettings.shared
    private var fontName: String? { fonts.fontName(for: note.fontID, defaultID: settings.defaultFontID) }
    private var fontSizeAdjustment: CGFloat { (note.fontSize ?? settings.defaultFontSize).adjustment }
    private var titleFontSize: CGFloat { 15 + fontSizeAdjustment }
    let note: StickyNote
    let tab: MemoTab
    let item: TodoItem
    @Binding var focusedItemID: UUID?

    @State private var strikeProgress: CGFloat = 0
    @State private var showPen = false
    @State private var isEditingText = false
    @State private var isRowHovered = false
    @State private var showReminder = false
    @State private var measuredTitleWidth: CGFloat = 0
    /// Bumped on every strike so a stale timer cannot end a newer flourish early.
    @State private var penGeneration = 0

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                toggleDone()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color(hex: note.penHex).opacity(0.72), lineWidth: 1.7)
                        .frame(width: 16, height: 16)

                    if item.isDone && hasContent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: note.penHex))
                    }
                }
                .frame(width: 20, height: 20)
                // A stroked circle only hit-tests along the stroke, so without a shape the
                // click has to land on the 1.7pt ring to count.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasContent)
            .opacity(hasContent ? 1 : 0.28)
            .help(hasContent ? (item.isDone ? L("완료 취소") : L("완료")) : L("할 일을 입력하면 완료할 수 있어요"))

            ZStack(alignment: .leading) {
                PlainEditableTextField(
                    text: Binding(
                        get: {
                            store.itemTitle(noteID: note.id, tabID: tab.id, itemID: item.id) ?? item.title
                        },
                        set: {
                            store.updateItemTitle(
                                noteID: note.id,
                                tabID: tab.id,
                                itemID: item.id,
                                title: $0
                            )
                        }
                    ),
                    placeholder: L("할 일 입력"),
                    fontSize: titleFontSize,
                    fontWeight: Self.titleFontWeight,
                    fontName: fontName,
                    textOpacity: item.isDone ? 0.38 : 0.76,
                    isFocused: focusedItemID == item.id,
                    placesCaretAtEndOnFocus: true,
                    onEditingChanged: {
                        isEditingText = $0
                        if $0 { focusedItemID = item.id }
                    },
                    onSubmit: {
                        focusedItemID = store.addItem(to: note.id, tabID: tab.id)
                    },
                    onMoveUp: { moveFocus(by: -1) },
                    onMoveDown: { moveFocus(by: 1) },
                    onDeleteEmpty: {
                        guard let previousID = store.deleteEmptyItemBackward(
                            noteID: note.id, tabID: tab.id, itemID: item.id
                        ) else { return false }
                        focusedItemID = previousID
                        return true
                    }
                )
                .frame(height: 26 + max(0, fontSizeAdjustment))

                StrikeLine(
                    color: Color(hex: note.penHex),
                    style: note.penStyle,
                    textWidth: measuredTitleWidth,
                    progress: strikeProgress,
                    showPen: showPen
                )
                .allowsHitTesting(false)
            }
            .frame(height: 28 + max(0, fontSizeAdjustment))

            Button {
                showReminder = true
            } label: {
                Image(systemName: item.reminderAt == nil ? "bell" : "bell.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: note.penHex).opacity(0.6))
            .opacity(item.reminderAt != nil || isRowHovered || isEditingText ? 1 : 0)
            .disabled(!hasContent || item.isDone)
            .help(item.reminderAt.map { L("알림 예약") + ": " + $0.formatted(date: .abbreviated, time: .shortened) } ?? L("알림 예약"))
            .popover(isPresented: $showReminder) {
                ReminderEditor(noteID: note.id, tabID: tab.id, item: item, onClose: { showReminder = false })
                    .environmentObject(store)
                    .presentationBackground(Color(hex: note.paperHex))
                    .preferredColorScheme(.light)
                    .excludedFromScreenCapture()
            }

            Button {
                store.presentedDetailItemID = item.id
            } label: {
                Image(systemName: hasDetail ? "bubble.fill" : "plus.bubble")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: note.penHex).opacity(hasDetail ? 0.7 : 0.34))
            // An item with notes keeps its marker visible; an empty one only offers on hover.
            .opacity(hasDetail ? 1 : (isRowHovered || isEditingText ? 1 : 0))
            .disabled(!hasContent)
            .help(hasDetail ? L("세부사항 보기") : L("세부사항 추가"))
            .popover(isPresented: detailPresentation, arrowEdge: .trailing) {
                DetailEditor(
                    text: store.itemDetail(noteID: note.id, tabID: tab.id, itemID: item.id) ?? "",
                    title: store.itemTitle(noteID: note.id, tabID: tab.id, itemID: item.id) ?? item.title,
                    symbol: tab.stickerSymbol,
                    paperColor: Color(hex: note.paperHex),
                    inkColor: Color(hex: note.penHex),
                    fontName: fontName,
                    fontSizeAdjustment: fontSizeAdjustment,
                    onEdit: {
                        store.updateItemDetail(
                            noteID: note.id,
                            tabID: tab.id,
                            itemID: item.id,
                            detail: $0
                        )
                    },
                    onClose: { detailPresentation.wrappedValue = false }
                )
                // App switches keep this slip open; opening another detail replaces it.
                .interactiveDismissDisabled()
                // Paints the popover's own chrome, arrow included, so the slip reads as a piece
                // torn off this card rather than a system panel floating over it.
                .presentationBackground(Color(hex: note.paperHex))
                .excludedFromScreenCapture()
            }

            Button {
                store.deleteItem(noteID: note.id, tabID: tab.id, itemID: item.id)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: DesignTokens.rowDeleteButtonSize, height: DesignTokens.rowDeleteButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.24))
            .opacity(isRowHovered || isEditingText ? 1 : 0.12)
            .accessibilityLabel(L("삭제"))
            .help(L("항목 삭제 — ⌘Z로 실행 취소"))
        }
        .contentShape(Rectangle())
        .overlay(alignment: .bottomLeading) {
            if tab.items.last?.id != item.id {
                Rectangle()
                    .fill(.black.opacity(0.1))
                    .frame(height: 0.5)
                    // Like a ruled memo pad, the line starts after the checkbox and continues
                    // beneath the hover-only controls to the trailing edge.
                    .padding(.leading, 28)
                    .offset(y: 2.5)
                    .allowsHitTesting(false)
            }
        }
        .onHover { isRowHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isRowHovered)
        .onChange(of: currentTitle, initial: true) { _, title in
            measuredTitleWidth = width(of: title)
        }
        .onChange(of: titleFontSize) { _, _ in measuredTitleWidth = width(of: currentTitle) }
        .onChange(of: fontName) { _, _ in measuredTitleWidth = width(of: currentTitle) }
        .onAppear {
            // Persisted completions open already struck without replaying the flourish.
            strikeProgress = isStruck ? 1 : 0
        }
        .onChange(of: isStruck) { _, isStruck in
            penGeneration += 1
            let generation = penGeneration

            guard isStruck else {
                showPen = false
                withAnimation(.easeOut(duration: 0.18)) {
                    strikeProgress = 0
                }
                return
            }

            // Put the nib at the start in a separate render pass. If zero and one are written
            // in the same pass SwiftUI coalesces them, leaving the pen visible only at the end.
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                strikeProgress = 0
                showPen = true
            }

            DispatchQueue.main.async {
                guard penGeneration == generation else { return }

                withAnimation(.easeInOut(duration: 0.68)) {
                    strikeProgress = 1
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.76) {
                    guard penGeneration == generation else { return }
                    showPen = false
                }
            }
        }
    }

    private static let titleFontWeight: NSFont.Weight = .medium

    private var detailPresentation: Binding<Bool> {
        Binding(
            get: { store.presentedDetailItemID == item.id },
            set: { isPresented in
                if isPresented {
                    store.presentedDetailItemID = item.id
                } else if store.presentedDetailItemID == item.id {
                    // A previous popover may finish closing after the next one opens.
                    store.presentedDetailItemID = nil
                }
            }
        )
    }

    private var currentTitle: String {
        store.itemTitle(noteID: note.id, tabID: tab.id, itemID: item.id) ?? item.title
    }

    /// The strike stops where the text does, so it is measured in the field's own font. Measured
    /// on change rather than per render: hovering a row mutates `isRowHovered`, which re-runs the
    /// body, and laying out a string is not free at one call per row per pointer move.
    private func width(of title: String) -> CGFloat {
        let font = fontName.flatMap { NSFont(name: $0, size: titleFontSize) }
            ?? NSFont.systemFont(ofSize: titleFontSize, weight: Self.titleFontWeight)
        return (title as NSString).size(withAttributes: [.font: font]).width
    }

    /// The strike is drawn straight from the item so it can never disagree with the checkmark.
    private var isStruck: Bool {
        item.isDone && hasContent
    }

    private var hasContent: Bool {
        !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasDetail: Bool {
        !(item.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleDone() {
        store.toggleItem(noteID: note.id, tabID: tab.id, itemID: item.id)
    }

    private func moveFocus(by offset: Int) {
        guard let index = tab.items.firstIndex(where: { $0.id == item.id }) else { return }
        let target = index + offset
        guard tab.items.indices.contains(target) else { return }
        focusedItemID = tab.items[target].id
    }
}

/// One surface for both reading and writing, so there is no mode to switch between.
/// It borrows the card's paper, pen and sticker so the slip belongs to the note it hangs off.
///
/// The text is held locally rather than bound straight to the store: `TextEditor` writes back
/// during SwiftUI's own update pass, and a store write there publishes a change mid-update
/// ("Publishing changes from within view updates is not allowed"). `onChange` runs after the
/// pass has finished, which is why the write is routed through it.
private struct DetailEditor: View {
    let title: String
    let symbol: String
    let paperColor: Color
    let inkColor: Color
    let fontName: String?
    let fontSizeAdjustment: CGFloat
    let onEdit: (String) -> Void
    let onClose: () -> Void

    private let sourceText: String
    @State private var text: String
    @State private var showsClearConfirmation = false
    @FocusState private var isWriting: Bool

    init(
        text: String,
        title: String,
        symbol: String,
        paperColor: Color,
        inkColor: Color,
        fontName: String?,
        fontSizeAdjustment: CGFloat,
        onEdit: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        sourceText = text
        _text = State(initialValue: text)
        self.title = title
        self.symbol = symbol
        self.paperColor = paperColor
        self.inkColor = inkColor
        self.fontName = fontName
        self.fontSizeAdjustment = fontSizeAdjustment
        self.onEdit = onEdit
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rule
            writingArea
            rule
            footer
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: 300, height: 224)
        .background(paperColor)
        .background(PaperGrain())
        .environment(\.colorScheme, .light)
        .onChange(of: sourceText) { _, restored in
            if text != restored { text = restored }
        }
        .onChange(of: text) { _, edited in onEdit(edited) }
        // Opening the slip is always to read or write in it, so the caret is already there.
        // A hop past the presentation is what makes the focus stick in a popover.
        .task { isWriting = true }
        .alert(L("세부사항을 모두 지울까요?"), isPresented: $showsClearConfirmation) {
            Button(L("취소"), role: .cancel) { isWriting = true }
            Button(L("확인"), role: .destructive) {
                text = ""
                isWriting = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(inkColor.opacity(0.82))

            Text(title)
                .font(fontName.map { .custom($0, size: 12 + fontSizeAdjustment) } ?? .system(size: 12 + fontSizeAdjustment, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Button {
                showsClearConfirmation = true
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.65))
            .disabled(text.isEmpty)
            .accessibilityLabel(L("세부사항 모두 지우기"))
            .help(L("세부사항 모두 지우기"))
        }
        .padding(.bottom, 8)
    }

    /// The margin the text is written beside, the way a ruled pad has one.
    private var writingArea: some View {
        HStack(alignment: .top, spacing: 9) {
            Rectangle()
                .fill(inkColor.opacity(0.22))
                .frame(width: 1)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(L("무엇을, 어떻게 하는지 적어두세요"))
                        .font(fontName.map { .custom($0, size: 13 + fontSizeAdjustment) } ?? .system(size: 13 + fontSizeAdjustment))
                        .foregroundStyle(inkColor.opacity(0.3))
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .focused($isWriting)
                    .font(fontName.map { .custom($0, size: 13 + fontSizeAdjustment) } ?? .system(size: 13 + fontSizeAdjustment))
                    .lineSpacing(3)
                    .foregroundStyle(inkColor.opacity(0.78))
                    .tint(inkColor)
                    .scrollContentBackground(.hidden)
                    // `TextEditor` insets its own text; this pulls it back onto the margin.
                    .padding(.leading, -5)
            }
        }
        .padding(.vertical, 9)
    }

    private var rule: some View {
        Rectangle()
            .fill(inkColor.opacity(0.14))
            .frame(height: 1)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Text(L("자동 저장"))
                .foregroundStyle(.black.opacity(0.36))

            Spacer(minLength: 8)

            Button(action: onClose) {
                Text(L("⌘↩ 완료"))
                    .foregroundStyle(inkColor.opacity(0.66))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .help(L("닫기 — 적은 내용은 이미 저장돼 있어요"))
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .padding(.top, 8)
    }
}

private struct StrikeLine: View {
    let color: Color
    let style: PenStyle
    let textWidth: CGFloat
    let progress: CGFloat
    let showPen: Bool

    /// Where a borderless `NSTextField` starts drawing its text.
    private static let textInset: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let available = max(0, geometry.size.width - Self.textInset)
            let width = min(textWidth, available) * progress
            let centerY = geometry.size.height * 0.5

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(color.opacity(style.opacity))
                    .frame(width: width, height: style.strokeHeight)
                    .position(x: Self.textInset + width * 0.5, y: centerY)

                if showPen {
                    Image(systemName: style.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees(-14))
                        .position(x: Self.textInset + max(7, width), y: centerY - 8)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // The rotated nib intentionally sits above the strike and can pass the text field's
        // trailing edge. Clipping this layer cuts off the icon at both ends of the flourish.
    }
}
