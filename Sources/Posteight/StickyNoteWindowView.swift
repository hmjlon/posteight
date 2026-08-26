import AppKit
import SwiftUI

struct StickyNoteWindowView: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismissWindow) private var dismissWindow

    let noteID: UUID

    @State private var window: NSWindow?
    @State private var resizeStartFrame: NSRect?
    @State private var isMovingToTrash = false
    @State private var isPencilCaseOpen = false
    @State private var isCardHovered = false

    var body: some View {
        Group {
            if let note = store.notes.first(where: { $0.id == noteID }) {
                noteWindow(note)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        NoteWindowCoordinator.shared.remove(noteID)
                        dismissWindow(value: noteID)
                    }
            }
        }
    }

    private func noteWindow(_ note: StickyNote) -> some View {
        ZStack {
            FoldedCardSurface(
                paperColor: Color(hex: note.paperHex),
                inkColor: Color(hex: note.penHex)
            )

            VStack(spacing: 0) {
                noteHeader(note)

                StickyNoteView(
                    note: note,
                    onResizeChanged: { translation in
                        resizeWindow(note: note, translation: translation)
                    },
                    onResizeEnded: { translation in
                        finishResizingWindow(note: note, translation: translation)
                    },
                    isPencilCaseOpen: $isPencilCaseOpen
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(FoldedCardShape())
        }
        // The card fills the window instead of declaring its own size: a fixed size makes
        // SwiftUI resize the window under the drag, which is what made resizing stutter and
        // left an empty strip below the paper.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .scaleEffect(isMovingToTrash ? 0.08 : 1)
        .rotationEffect(isMovingToTrash ? .degrees(12) : .zero)
        .opacity(isMovingToTrash ? 0 : 1)
        .allowsHitTesting(!isMovingToTrash)
        .onHover { isCardHovered = $0 }
        .environment(\.colorScheme, .light)
        .background {
            NoteWindowConfigurator(note: note) { configuredWindow in
                NoteWindowCoordinator.shared.register(configuredWindow, for: noteID)
                if window !== configuredWindow {
                    window = configuredWindow
                }
            }
        }
        .onChange(of: settings.keepsNotesOnTop) { _, _ in
            window?.level = settings.noteWindowLevel
        }
    }

    private func noteHeader(_ note: StickyNote) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Image(systemName: note.stickerSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: note.penHex).opacity(0.82))

                WindowMoveHandle(onDragEnded: saveWindowPosition)
            }
            .frame(width: 20, height: 20)
            .help("카드를 끌어 이동")

            PlainEditableTextField(
                text: Binding(
                    get: { store.noteLabel(noteID) },
                    set: { store.updateNoteLabel(noteID, label: $0) }
                ),
                placeholder: "이름",
                fontSize: 10,
                fontWeight: .bold,
                textOpacity: 0.42
            )
            .frame(maxWidth: 132, alignment: .leading)
            .frame(height: 18)
            .help("이 포스트잇의 이름 — 업무, 학업처럼 분류로 쓰세요")

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Button {
                    isPencilCaseOpen.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 20, height: 20)
                }
                .help("카드 꾸미기")

                Button {
                    moveToTrash()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 19, height: 20)
                }
                .help("삭제")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary.opacity(0.54))
            .opacity(isCardHovered || isPencilCaseOpen ? 1 : 0.16)
            .animation(.easeOut(duration: 0.14), value: isCardHovered)
            .animation(.easeOut(duration: 0.14), value: isPencilCaseOpen)
        }
        .padding(.leading, 13)
        .padding(.trailing, FoldedCardMetrics.foldSize + 7)
        .frame(height: Self.titlebarHeight)
    }

    static let titlebarHeight: CGFloat = 32

    private func resizeWindow(note: StickyNote, translation: CGSize) {
        guard let window else { return }

        let startFrame = resizeStartFrame ?? window.frame
        if resizeStartFrame == nil {
            resizeStartFrame = startFrame
        }

        // With a full size content view the card fills the frame, so the stored size is the
        // window size.
        let size = clampedSize(note: note, translation: translation)
        window.setContentSize(NSSize(width: size.width, height: size.height))

        var adjustedFrame = window.frame
        adjustedFrame.origin.x = startFrame.minX
        adjustedFrame.origin.y = startFrame.maxY - adjustedFrame.height
        window.setFrame(adjustedFrame, display: true)
    }

    private func finishResizingWindow(note: StickyNote, translation: CGSize) {
        resizeWindow(note: note, translation: translation)
        let size = clampedSize(note: note, translation: translation)
        store.resizeNote(noteID, to: size)
        saveWindowPosition()
        resizeStartFrame = nil
    }

    private func clampedSize(note: StickyNote, translation: CGSize) -> NoteSize {
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

    private func saveWindowPosition() {
        guard let window else { return }
        let referenceFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        store.updateNotePosition(
            noteID,
            position: NotePoint(
                x: window.frame.midX - referenceFrame.minX,
                y: referenceFrame.maxY - window.frame.midY
            )
        )
    }

    private func moveToTrash() {
        guard !isMovingToTrash else { return }

        withAnimation(.easeInOut(duration: 0.32)) {
            isMovingToTrash = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            store.moveNoteToTrash(noteID)
            NoteWindowCoordinator.shared.remove(noteID)
            dismissWindow(value: noteID)
        }
    }
}

private struct NoteWindowConfigurator: NSViewRepresentable {
    let note: StickyNote
    let onWindowAvailable: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWindow(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(for: nsView, coordinator: context.coordinator)
    }

    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onWindowAvailable(window)
            guard !coordinator.didConfigure else { return }
            coordinator.didConfigure = true

            window.title = note.title
            window.level = AppSettings.shared.noteWindowLevel
            window.isMovable = true
            window.isMovableByWindowBackground = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.remove(.resizable)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentMinSize = NSSize(
                width: DesignTokens.minimumNoteSize.width,
                height: DesignTokens.minimumNoteSize.height
            )
            window.contentMaxSize = NSSize(
                width: DesignTokens.maximumNoteSize.width,
                height: DesignTokens.maximumNoteSize.height
            )
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.setContentSize(NSSize(width: note.size.width, height: note.size.height))

            let referenceFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
            window.setFrameOrigin(
                NSPoint(
                    x: referenceFrame.minX + note.position.x - window.frame.width * 0.5,
                    y: referenceFrame.maxY - note.position.y - window.frame.height * 0.5
                )
            )
        }
    }

    final class Coordinator {
        var didConfigure = false
    }
}
