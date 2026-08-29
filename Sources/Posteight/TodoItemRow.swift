import AppKit
import SwiftUI

struct TodoItemRow: View {
    @EnvironmentObject private var store: PosteightStore
    let note: StickyNote
    let tab: MemoTab
    let item: TodoItem
    @Binding var focusedItemID: UUID?

    @State private var showPen = false
    @State private var isEditingText = false
    @State private var isRowHovered = false
    @State private var showDetail = false

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
                    fontSize: Self.titleFontSize,
                    fontWeight: Self.titleFontWeight,
                    textOpacity: item.isDone ? 0.38 : 0.76,
                    isFocused: focusedItemID == item.id,
                    onEditingChanged: { isEditingText = $0 },
                    onSubmit: {
                        focusedItemID = store.addItem(to: note.id, tabID: tab.id)
                    },
                    onMoveUp: { moveFocus(by: -1) },
                    onMoveDown: { moveFocus(by: 1) }
                )
                .frame(height: 26)

                StrikeLine(
                    color: Color(hex: note.penHex),
                    style: note.penStyle,
                    textWidth: titleWidth,
                    progress: isStruck ? 1 : 0,
                    showPen: showPen
                )
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.68), value: isStruck)
            }
            .frame(height: 28)

            Button {
                showDetail = true
            } label: {
                Image(systemName: hasDetail ? "text.alignleft" : "plus.bubble")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: note.penHex).opacity(hasDetail ? 0.7 : 0.34))
            // An item with notes keeps its marker visible; an empty one only offers on hover.
            .opacity(hasDetail ? 1 : (isRowHovered || isEditingText ? 1 : 0))
            .disabled(!hasContent)
            .help(hasDetail ? L("세부사항 보기") : L("세부사항 추가"))
            .popover(isPresented: $showDetail, arrowEdge: .trailing) {
                DetailEditor(
                    text: store.itemDetail(noteID: note.id, tabID: tab.id, itemID: item.id) ?? "",
                    title: store.itemTitle(noteID: note.id, tabID: tab.id, itemID: item.id) ?? item.title,
                    symbol: note.stickerSymbol,
                    paperColor: Color(hex: note.paperHex),
                    inkColor: Color(hex: note.penHex),
                    onEdit: {
                        store.updateItemDetail(
                            noteID: note.id,
                            tabID: tab.id,
                            itemID: item.id,
                            detail: $0
                        )
                    },
                    onClose: { showDetail = false }
                )
                // Paints the popover's own chrome, arrow included, so the slip reads as a piece
                // torn off this card rather than a system panel floating over it.
                .presentationBackground(Color(hex: note.paperHex))
            }

            Button {
                store.deleteItem(noteID: note.id, tabID: tab.id, itemID: item.id)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.24))
            .opacity(isRowHovered || isEditingText ? 1 : 0.12)
            .help(L("삭제"))
        }
        .contentShape(Rectangle())
        .onHover { isRowHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isRowHovered)
        // Only the travelling pen is a one-off flourish; the line itself follows the item.
        .onChange(of: isStruck) { _, isStruck in
            guard isStruck else {
                showPen = false
                return
            }

            showPen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.76) {
                showPen = false
            }
        }
    }

    private static let titleFontSize: CGFloat = 15
    private static let titleFontWeight: NSFont.Weight = .medium

    /// The strike stops where the text does, so it is measured in the field's own font.
    private var titleWidth: CGFloat {
        let title = store.itemTitle(noteID: note.id, tabID: tab.id, itemID: item.id) ?? item.title
        let font = NSFont.systemFont(ofSize: Self.titleFontSize, weight: Self.titleFontWeight)
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
    let onEdit: (String) -> Void
    let onClose: () -> Void

    @State private var text: String
    @FocusState private var isWriting: Bool

    init(
        text: String,
        title: String,
        symbol: String,
        paperColor: Color,
        inkColor: Color,
        onEdit: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        _text = State(initialValue: text)
        self.title = title
        self.symbol = symbol
        self.paperColor = paperColor
        self.inkColor = inkColor
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
        .onChange(of: text) { _, edited in onEdit(edited) }
        // Opening the slip is always to read or write in it, so the caret is already there.
        // A hop past the presentation is what makes the focus stick in a popover.
        .task { isWriting = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(inkColor.opacity(0.82))

            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
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
                        .font(.system(size: 13))
                        .foregroundStyle(inkColor.opacity(0.3))
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .focused($isWriting)
                    .font(.system(size: 13))
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
        .clipped()
    }
}
