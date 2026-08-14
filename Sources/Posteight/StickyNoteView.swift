import SwiftUI

struct StickyNoteView: View {
    @EnvironmentObject private var store: PosteightStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
        .overlay {
            ZStack {
                Rectangle()
                    .stroke(.white.opacity(0.34), lineWidth: 0.8)

                Rectangle()
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 9)
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
        .background {
            ZStack {
                // Paper is opaque: a sticky note that shows the desktop through it is
                // unreadable over busy windows.
                Rectangle()
                    .fill(Color(hex: note.paperHex))

                if !reduceTransparency {
                    LinearGradient(
                        colors: [
                            .white.opacity(0.2),
                            .clear,
                            Color(hex: note.penHex).opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                NotebookLines()
                    .padding(.top, 34)
                    .padding(.horizontal, 12)
            }
        }
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
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.075))
                        .frame(height: 0.7)

                    Rectangle()
                        .fill(.white.opacity(0.16))
                        .frame(height: 0.5)
                        .offset(y: 0.7)
                }
                .offset(y: CGFloat(index) * lineSpacing)
            }
        }
        .allowsHitTesting(false)
    }
}
