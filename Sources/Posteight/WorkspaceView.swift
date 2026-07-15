import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var store: PosteightStore
    @State private var isShowingDailyLog = false
    @State private var isShowingTrash = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            workspaceBackground

            ForEach(store.notes) { note in
                DraggableStickyNote(note: note)
            }

            workspaceBar
                .padding(18)
        }
        .sheet(isPresented: $isShowingDailyLog) {
            DailyLogPreviewView()
                .environmentObject(store)
        }
        .sheet(isPresented: $isShowingTrash) {
            TrashView()
                .environmentObject(store)
        }
    }

    private var workspaceBackground: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
    }

    private var workspaceBar: some View {
        HStack(spacing: 8) {
            Text("Posteight")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.74))

            Button {
                store.addNote()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .help("새 포스트잇")

            Button {
                isShowingDailyLog = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 22, height: 22)
            }
            .help("오늘 기록 미리보기")

            Button {
                isShowingTrash = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: store.trashedNotes.isEmpty ? "trash" : "trash.fill")
                        .frame(width: 22, height: 22)

                    if !store.trashedNotes.isEmpty {
                        Text("\(store.trashedNotes.count)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 13, height: 13)
                            .background(Color.black.opacity(0.72), in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
            }
            .help("휴지통")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Rectangle())
        .overlay {
            Rectangle()
                .stroke(.black.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct DraggableStickyNote: View {
    @EnvironmentObject private var store: PosteightStore
    let note: StickyNote
    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var isMovingToTrash = false

    var body: some View {
        let size = currentSize
        let resizePositionOffset = currentResizePositionOffset

        StickyNoteView(
            note: note,
            onDelete: {
                playDeleteAnimation()
            },
            onMoveChanged: { translation in
                dragOffset = translation
            },
            onMoveEnded: { translation in
                store.moveNote(note.id, by: translation)
                dragOffset = .zero
            },
            onResizeChanged: { translation in
                resizeDelta = translation
            },
            onResizeEnded: { translation in
                let finalSize = clampedSize(for: translation)
                let effectiveDelta = CGSize(
                    width: finalSize.width - note.size.width,
                    height: finalSize.height - note.size.height
                )

                store.resizeNote(note.id, to: finalSize)
                store.moveNote(note.id, by: CGSize(width: effectiveDelta.width / 2, height: effectiveDelta.height / 2))
                resizeDelta = .zero
            }
        )
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .modifier(TrashMoveModifier(isActive: isMovingToTrash, notePosition: note.position))
            .position(
                x: note.position.x + dragOffset.width + resizePositionOffset.width,
                y: note.position.y + dragOffset.height + resizePositionOffset.height
            )
            .allowsHitTesting(!isMovingToTrash)
    }

    private func playDeleteAnimation() {
        guard !isMovingToTrash else { return }
        withAnimation(.easeInOut(duration: 0.42)) {
            isMovingToTrash = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            store.moveNoteToTrash(note.id)
        }
    }

    private var currentSize: NoteSize {
        clampedSize(for: resizeDelta)
    }

    private var currentResizePositionOffset: CGSize {
        CGSize(
            width: (currentSize.width - note.size.width) / 2,
            height: (currentSize.height - note.size.height) / 2
        )
    }

    private func clampedSize(for translation: CGSize) -> NoteSize {
        NoteSize(
            width: min(
                max(note.size.width + translation.width, DesignTokens.minimumNoteSize.width),
                DesignTokens.maximumNoteSize.width
            ),
            height: min(
                max(note.size.height + translation.height, DesignTokens.minimumNoteSize.height),
                DesignTokens.maximumNoteSize.height
            )
        )
    }
}

private struct TrashMoveModifier: ViewModifier {
    let isActive: Bool
    let notePosition: NotePoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 0.08 : 1)
            .rotationEffect(isActive ? .degrees(18) : .zero)
            .offset(isActive ? CGSize(width: 110 - notePosition.x, height: 28 - notePosition.y) : .zero)
            .opacity(isActive ? 0 : 1)
            .overlay(alignment: .bottomTrailing) {
                if isActive {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.black.opacity(0.55))
                        .offset(x: 14, y: 14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
    }
}
