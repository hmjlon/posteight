import SwiftUI

struct StickyNoteView: View {
    @EnvironmentObject private var store: PosteightStore
    let note: StickyNote
    let onResizeChanged: (CGSize) -> Void
    let onResizeEnded: (CGSize) -> Void
    @Binding var isPencilCaseOpen: Bool
    @FocusState private var focusedItemID: UUID?

    var body: some View {
        noteBody
        .overlay(alignment: .bottomTrailing) {
            resizeHandle
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isPencilCaseOpen)
    }

    private var noteBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            PlainEditableTextField(
                text: Binding(
                    get: { store.noteTitle(note.id) ?? note.title },
                    set: { store.updateNoteTitle(note.id, title: $0) }
                ),
                fontSize: 13,
                fontWeight: .medium,
                textOpacity: 0.72
            )
            .frame(height: 22)

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
            .padding(.top, isPencilCaseOpen ? 8 : 5)

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
        .padding(.horizontal, 13)
        .padding(.top, 9)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
