import SwiftUI

struct StickyNoteView: View {
    @EnvironmentObject private var store: PosteightStore
    let note: StickyNote
    let onDelete: () -> Void
    let onMoveChanged: (CGSize) -> Void
    let onMoveEnded: (CGSize) -> Void
    let onResizeChanged: (CGSize) -> Void
    let onResizeEnded: (CGSize) -> Void
    @State private var isPencilCaseOpen = false
    @FocusState private var focusedItemID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if isPencilCaseOpen {
                PencilCaseView(note: note)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }

            VStack(spacing: 5) {
                ForEach(note.items) { item in
                    TodoItemRow(note: note, item: item, focusedItemID: $focusedItemID)
                }
            }
            .padding(.top, isPencilCaseOpen ? 8 : 32)

            Spacer(minLength: 0)

            Button {
                focusedItemID = store.addItem(to: note.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("할 일 추가")
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.58))
            }
            .buttonStyle(.plain)
            .help("할 일 추가")
        }
        .padding(13)
        .background {
            ZStack {
                Rectangle()
                    .fill(Color(hex: note.paperHex))

                NotebookLines()
                    .padding(.top, 44)
                    .padding(.horizontal, 12)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            resizeHandle
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.36))
                .frame(height: 1)
        }
        .overlay {
            Rectangle()
                .stroke(.black.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isPencilCaseOpen)
    }

    private var header: some View {
        HStack(spacing: 8) {
            moveHandle

            Image(systemName: note.stickerSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: note.penHex).opacity(0.88))
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.38), in: Rectangle())

            PlainEditableTextField(
                text: Binding(
                    get: { store.noteTitle(note.id) ?? note.title },
                    set: { store.updateNoteTitle(note.id, title: $0) }
                ),
                fontSize: 13,
                fontWeight: .regular,
                textOpacity: 0.58
            )
            .frame(height: 22)

            Button {
                isPencilCaseOpen.toggle()
            } label: {
                Image(systemName: "pencil.and.outline")
                    .frame(width: 21, height: 21)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.62))
            .help("필통")

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.42))
            .help("삭제")
        }
    }

    private var moveHandle: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black.opacity(0.38))
            .frame(width: 18, height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        onMoveChanged(value.translation)
                    }
                    .onEnded { value in
                        onMoveEnded(value.translation)
                    }
            )
            .help("포스트잇 이동")
    }

    private var resizeHandle: some View {
        ZStack(alignment: .bottomTrailing) {
            Path { path in
                path.move(to: CGPoint(x: 5, y: 21))
                path.addLine(to: CGPoint(x: 21, y: 5))
                path.move(to: CGPoint(x: 11, y: 22))
                path.addLine(to: CGPoint(x: 22, y: 11))
                path.move(to: CGPoint(x: 17, y: 23))
                path.addLine(to: CGPoint(x: 23, y: 17))
            }
            .stroke(.black.opacity(0.28), lineWidth: 1.4)
        }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    onResizeChanged(value.translation)
                }
                .onEnded { value in
                    onResizeEnded(value.translation)
                }
        )
        .help("크기 조절")
    }
}

private struct NotebookLines: View {
    private let lineSpacing: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            let lineCount = max(0, Int(geometry.size.height / lineSpacing))

            ForEach(0..<lineCount, id: \.self) { index in
                Rectangle()
                    .fill(.gray.opacity(0.13))
                    .frame(height: 0.8)
                    .offset(y: CGFloat(index) * lineSpacing)
            }
        }
        .allowsHitTesting(false)
    }
}
