import SwiftUI

struct TodoItemRow: View {
    @EnvironmentObject private var store: PosteightStore
    let note: StickyNote
    let item: TodoItem
    let focusedItemID: FocusState<UUID?>.Binding

    @State private var strikeProgress: CGFloat = 0
    @State private var showPen = false
    @State private var isEditingText = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                toggleDone()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color(hex: note.penHex).opacity(0.72), lineWidth: 1.7)
                        .frame(width: 16, height: 16)

                    if item.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: note.penHex))
                    }
                }
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "완료 취소" : "완료")

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
                    onEditingChanged: { isEditingText = $0 },
                    onSubmit: {
                        focusedItemID.wrappedValue = store.addItem(to: note.id)
                    }
                )
                .frame(height: 26)
                .focused(focusedItemID, equals: item.id)

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
            .help("삭제")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditingText else { return }
            toggleDone()
        }
        .onAppear {
            strikeProgress = item.isDone ? 1 : 0
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

    private func toggleDone() {
        store.toggleItem(noteID: note.id, itemID: item.id)
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
