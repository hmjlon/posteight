import AppKit
import SwiftUI

struct StickyNoteView: View {
    @EnvironmentObject private var store: PosteightStore
    let note: StickyNote
    let onResizeChanged: (CGSize) -> Void
    let onResizeEnded: (CGSize) -> Void
    @Binding var isPencilCaseOpen: Bool
    @State private var focusedItemID: UUID?
    @State private var resizeAnchor: CGPoint?

    var body: some View {
        noteBody
        .overlay(alignment: .trailing) {
            horizontalResizeHandle
        }
        .overlay(alignment: .bottom) {
            verticalResizeHandle
        }
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

            // Without a scroll area a long list overflows the card in both directions and
            // collides with the header, so the list gets the leftover height and nothing else.
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
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
                                .id(item.id)
                        }
                    }
                    .padding(.top, isPencilCaseOpen ? 8 : 5)
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
                .onChange(of: focusedItemID) { _, itemID in
                    guard let itemID else { return }

                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(itemID, anchor: .bottom)
                    }
                }
            }

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

    /// Right edge, bottom edge, and corner, so a note can be resized in either axis or both.
    private var horizontalResizeHandle: some View {
        Color.clear
            .frame(width: 9)
            .padding(.top, 6)
            .padding(.bottom, 26)
            .contentShape(Rectangle())
            .onHover { isHovering in
                setCursor(isHovering ? .resizeLeftRight : .arrow)
            }
            .gesture(resizeGesture { CGSize(width: $0.width, height: 0) })
            .help("가로 크기 조절")
    }

    private var verticalResizeHandle: some View {
        Color.clear
            .frame(height: 9)
            .padding(.leading, 6)
            .padding(.trailing, 26)
            .contentShape(Rectangle())
            .onHover { isHovering in
                setCursor(isHovering ? .resizeUpDown : .arrow)
            }
            .gesture(resizeGesture { CGSize(width: 0, height: $0.height) })
            .help("세로 크기 조절")
    }

    private func resizeGesture(_ axis: @escaping (CGSize) -> CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                onResizeChanged(axis(dragDelta()))
            }
            .onEnded { _ in
                onResizeEnded(axis(dragDelta()))
                resizeAnchor = nil
            }
    }

    /// The window resizes under the pointer, so the gesture's own translation feeds back on
    /// itself and the note stutters. Screen coordinates stay put while the window changes.
    private func dragDelta() -> CGSize {
        let location = NSEvent.mouseLocation

        guard let anchor = resizeAnchor else {
            resizeAnchor = location
            return .zero
        }

        return CGSize(width: location.x - anchor.x, height: anchor.y - location.y)
    }

    private func setCursor(_ cursor: NSCursor) {
        cursor.set()
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
        .onHover { isHovering in
            setCursor(isHovering ? .crosshair : .arrow)
        }
        .gesture(resizeGesture { $0 })
        .help("대각선 크기 조절")
    }
}
