import SwiftUI

struct TodoItemRow: View {
    @EnvironmentObject private var store: PosteightStore
    let note: StickyNote
    let item: TodoItem
    @Binding var focusedItemID: UUID?

    @State private var strikeProgress: CGFloat = 0
    @State private var showPen = false
    @State private var isEditingText = false
    @State private var isRowHovered = false

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
            }
            .buttonStyle(.plain)
            .disabled(!hasContent)
            .opacity(hasContent ? 1 : 0.28)
            .help(hasContent ? (item.isDone ? "완료 취소" : "완료") : "할 일을 입력하면 완료할 수 있어요")

            ZStack(alignment: .leading) {
                PlainEditableTextField(
                    text: Binding(
                        get: { store.itemTitle(noteID: note.id, itemID: item.id) ?? item.title },
                        set: { store.updateItemTitle(noteID: note.id, itemID: item.id, title: $0) }
                    ),
                    placeholder: "할 일 입력",
                    fontSize: 15,
                    fontWeight: .medium,
                    textOpacity: item.isDone ? 0.38 : 0.76,
                    isFocused: focusedItemID == item.id,
                    onEditingChanged: { isEditingText = $0 },
                    onSubmit: {
                        focusedItemID = store.addItem(to: note.id)
                    },
                    onMoveUp: { moveFocus(by: -1) },
                    onMoveDown: { moveFocus(by: 1) }
                )
                .frame(height: 26)

                StrikeLine(
                    color: Color(hex: note.penHex),
                    style: note.penStyle,
                    progress: strikeProgress,
                    showPen: showPen
                )
                .allowsHitTesting(false)
            }
            .frame(height: 28)

            Button {
                store.deleteItem(noteID: note.id, itemID: item.id)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.24))
            .opacity(isRowHovered || isEditingText ? 1 : 0.12)
            .help("삭제")
        }
        .contentShape(Rectangle())
        .onHover { isRowHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isRowHovered)
        .onAppear {
            strikeProgress = item.isDone && hasContent ? 1 : 0
        }
        .onChange(of: item.isDone) { _, isDone in
            if isDone {
                showPen = true
                strikeProgress = 0

                withAnimation(.easeInOut(duration: 0.68)) {
                    strikeProgress = 1
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.76) {
                    showPen = false
                }
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    strikeProgress = 0
                    showPen = false
                }
            }
        }
    }

    private var hasContent: Bool {
        !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleDone() {
        store.toggleItem(noteID: note.id, itemID: item.id)
    }

    private func moveFocus(by offset: Int) {
        guard let index = note.items.firstIndex(where: { $0.id == item.id }) else { return }
        let target = index + offset
        guard note.items.indices.contains(target) else { return }
        focusedItemID = note.items[target].id
    }
}

private struct StrikeLine: View {
    let color: Color
    let style: PenStyle
    let progress: CGFloat
    let showPen: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width * progress)
            let centerY = geometry.size.height * 0.5

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(color.opacity(style.opacity))
                    .frame(width: width, height: style.strokeHeight)
                    .position(x: width * 0.5, y: centerY)

                if showPen {
                    Image(systemName: style.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees(-14))
                        .position(x: max(7, width), y: centerY - 8)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
    }
}
