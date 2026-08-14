import AppKit
import SwiftUI

struct StickyNoteWindowView: View {
    @EnvironmentObject private var store: PosteightStore
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let noteID: UUID

    @State private var window: NSWindow?
    @State private var resizeStartFrame: NSRect?
    @State private var liveSize: NoteSize?
    @State private var isMovingToTrash = false
    @State private var isPencilCaseOpen = false

    var body: some View {
        Group {
            if let note = store.notes.first(where: { $0.id == noteID }) {
                noteWindow(note)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        dismissWindow(value: noteID)
                    }
            }
        }
    }

    private func noteWindow(_ note: StickyNote) -> some View {
        let displayedSize = liveSize ?? note.size

        return VStack(spacing: 0) {
            noteHeader(note)
                .frame(height: Self.titlebarHeight)

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
            .frame(width: displayedSize.width, height: displayedSize.height)
        }
        .frame(
            width: displayedSize.width,
            height: displayedSize.height + Self.titlebarHeight
        )
        .ignoresSafeArea(.container, edges: .top)
        .scaleEffect(isMovingToTrash ? 0.08 : 1)
        .rotationEffect(isMovingToTrash ? .degrees(12) : .zero)
        .opacity(isMovingToTrash ? 0 : 1)
        .allowsHitTesting(!isMovingToTrash)
        .background {
            NoteWindowConfigurator(note: note) { configuredWindow in
                if window !== configuredWindow {
                    window = configuredWindow
                }
            }
        }
    }

    private func noteHeader(_ note: StickyNote) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.45))

                WindowMoveHandle(onDragEnded: saveWindowPosition)
            }
            .frame(width: 22, height: 22)
            .help("포스트잇 이동")

            Image(systemName: note.stickerSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: note.penHex).opacity(0.9))
                .frame(width: 20, height: 20)

            Spacer(minLength: 0)

            Button {
                isPencilCaseOpen.toggle()
            } label: {
                Image(systemName: "pencil.and.outline")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary.opacity(0.62))
            .help("필통")

            Button {
                moveToTrash()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 19, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary.opacity(0.46))
            .help("삭제")
        }
        .padding(.horizontal, 10)
        .background {
            ZStack {
                if reduceTransparency {
                    Rectangle()
                        .fill(Color(hex: note.paperHex))
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)

                    Rectangle()
                        .fill(Color(hex: note.paperHex).opacity(0.24))

                    LinearGradient(
                        colors: [.white.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(height: 0.8)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.08))
                .frame(height: 1)
        }
    }

    private static let titlebarHeight: CGFloat = 32

    private func resizeWindow(note: StickyNote, translation: CGSize) {
        guard let window else { return }

        let startFrame = resizeStartFrame ?? window.frame
        if resizeStartFrame == nil {
            resizeStartFrame = startFrame
        }

        let size = clampedSize(note: note, translation: translation)
        liveSize = size
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
        liveSize = nil
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
            window.level = .floating
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
