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
    @State private var editingTabID: UUID?
    @State private var tabNameDraft = ""

    var body: some View {
        Group {
            if let note = store.notes.first(where: { $0.id == noteID }),
               let selectedTab = note.selectedTab {
                noteWindow(note, selectedTab: selectedTab)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        closeCard()
                    }
            }
        }
    }

    private func noteWindow(_ note: StickyNote, selectedTab: MemoTab) -> some View {
        ZStack {
            MemoCardSurface(paperColor: Color(hex: note.paperHex))

            VStack(spacing: 0) {
                memoTabBar(note: note, selectedTab: selectedTab)

                StickyNoteView(
                    note: note,
                    tab: selectedTab,
                    onResizeChanged: { translation in
                        resizeWindow(translation: translation)
                    },
                    onResizeEnded: { translation in
                        finishResizingWindow(translation: translation)
                    },
                    onDelete: { moveToTrash(note) },
                    isPencilCaseOpen: $isPencilCaseOpen
                )
                .id(selectedTab.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(MemoCardShape())
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
            NoteWindowConfigurator(note: note, windowTitle: selectedTab.title) { configuredWindow in
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

    private func memoTabBar(note: StickyNote, selectedTab: MemoTab) -> some View {
        GeometryReader { geometry in
            let controlsWidth = MemoSurfaceMetrics.trailingControlsWidth
            let addButtonWidth = MemoSurfaceMetrics.addTabButtonWidth
            let availableTabWidth = max(0, geometry.size.width - controlsWidth - addButtonWidth)

            HStack(alignment: .bottom, spacing: 0) {
                memoTabs(note: note, selectedTab: selectedTab, availableWidth: availableTabWidth)
                    .frame(width: availableTabWidth)

                Button {
                    commitTabName(note: note)
                    _ = store.addTab(to: note.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: addButtonWidth, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.black.opacity(0.48))
                .help("이 메모에 새 탭 추가")
                .padding(.bottom, 3)

                tabBarControls
                    .frame(width: controlsWidth)
            }
        }
        .frame(height: MemoSurfaceMetrics.tabBarHeight, alignment: .bottom)
        .background {
            Color(hex: note.paperHex)
                .overlay(Color.black.opacity(0.055))
        }
    }

    private func memoTabs(
        note: StickyNote,
        selectedTab: MemoTab,
        availableWidth: CGFloat
    ) -> some View {
        let tabCount = max(note.tabs.count, 1)
        let dividedWidth = availableWidth / CGFloat(tabCount)
        let tabWidth = min(MemoSurfaceMetrics.maximumTabWidth, dividedWidth)

        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(note.tabs) { tab in
                memoTab(
                    note,
                    tab: tab,
                    isSelected: tab.id == selectedTab.id,
                    width: tabWidth
                )
                .id(tab.id)
            }
        }
        .frame(width: availableWidth, height: MemoSurfaceMetrics.tabBarHeight, alignment: .bottomLeading)
        .clipped()
    }

    @ViewBuilder
    private func memoTab(
        _ note: StickyNote,
        tab: MemoTab,
        isSelected: Bool,
        width: CGFloat
    ) -> some View {
        let showsSticker = width >= 54
        let horizontalPadding: CGFloat = width >= 74 ? 10 : 5

        if isSelected {
            ZStack {
                memoTabSurface(note, isSelected: true)

                if editingTabID == tab.id {
                    PlainEditableTextField(
                        text: $tabNameDraft,
                        placeholder: tab.name,
                        fontSize: 10,
                        fontWeight: .semibold,
                        textOpacity: 0.68,
                        isFocused: true,
                        onEditingChanged: { isEditing in
                            if !isEditing, editingTabID == tab.id {
                                commitTabName(note: note)
                            }
                        },
                        onSubmit: {
                            commitTabName(note: note)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 18)
                    .padding(.horizontal, horizontalPadding)
                } else {
                    Button {
                        beginEditing(tab)
                    } label: {
                        tabLabel(note: note, tab: tab, showsSticker: showsSticker, isSelected: true)
                            .padding(.horizontal, horizontalPadding)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: width, height: MemoSurfaceMetrics.activeTabHeight)
            .clipped()
            .help("현재 탭 — 다시 클릭하면 이름을 수정할 수 있어요")
            .accessibilityAddTraits(.isSelected)
        } else {
            Button {
                commitTabName(note: note)
                withAnimation(.easeOut(duration: 0.16)) {
                    store.selectTab(noteID: note.id, tabID: tab.id)
                }
            } label: {
                ZStack {
                    memoTabSurface(note, isSelected: false)

                    tabLabel(note: note, tab: tab, showsSticker: showsSticker, isSelected: false)
                        .padding(.horizontal, horizontalPadding)
                }
            }
            .buttonStyle(.plain)
            .frame(width: width, height: MemoSurfaceMetrics.inactiveTabHeight)
            .contentShape(MemoTabShape())
            .help("\(tab.name) 탭으로 이동")
            .padding(.bottom, 3)
            .clipped()
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 0.5, height: 14)
                    .padding(.bottom, 8)
            }
        }
    }

    private func tabLabel(
        note: StickyNote,
        tab: MemoTab,
        showsSticker: Bool,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: showsSticker ? 6 : 0) {
            if showsSticker {
                ZStack {
                    Image(systemName: note.stickerSymbol)
                        .font(.system(size: isSelected ? 10 : 9, weight: .semibold))

                    if isSelected {
                        WindowMoveHandle(onDragEnded: saveWindowPosition)
                    }
                }
                .frame(width: 15, height: 18)
            }

            Text(tab.name)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(hex: note.penHex).opacity(isSelected ? 0.72 : 0.58))
        .clipped()
    }

    private func memoTabSurface(_ note: StickyNote, isSelected: Bool) -> some View {
        MemoTabShape()
            .fill(Color(hex: note.paperHex))
            .overlay {
                if !isSelected {
                    Color.black.opacity(0.035)
                        .clipShape(MemoTabShape())
                }
            }
            .opacity(isSelected ? 1 : 0.76)
    }

    private func beginEditing(_ tab: MemoTab) {
        editingTabID = tab.id
        tabNameDraft = tab.name
    }

    private func commitTabName(note: StickyNote) {
        guard let editingTabID else { return }
        store.updateTabName(noteID: note.id, tabID: editingTabID, name: tabNameDraft)
        self.editingTabID = nil
        tabNameDraft = ""
    }

    private var tabBarControls: some View {
        HStack(spacing: 1) {
            Button {
                isPencilCaseOpen.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 24, height: 28)
            }
            .help("메모 꾸미기")

            Button {
                closeCard()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 28)
            }
            .help("닫기 — 메모는 그대로 있어요")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.black.opacity(0.48))
        .opacity(isCardHovered || isPencilCaseOpen ? 1 : 0.42)
        .animation(.easeOut(duration: 0.14), value: isCardHovered)
        .animation(.easeOut(duration: 0.14), value: isPencilCaseOpen)
        .padding(.bottom, 3)
    }

    private func resizeWindow(translation: CGSize) {
        guard let window else { return }

        let startFrame = resizeStartFrame ?? window.frame
        if resizeStartFrame == nil {
            resizeStartFrame = startFrame
        }

        // With a full size content view the card fills the frame, so the stored size is the
        // window size.
        let size = clampedSize(startFrame: startFrame, translation: translation)
        window.setContentSize(NSSize(width: size.width, height: size.height))

        var adjustedFrame = window.frame
        adjustedFrame.origin.x = startFrame.minX
        adjustedFrame.origin.y = startFrame.maxY - adjustedFrame.height
        window.setFrame(adjustedFrame, display: true)
    }

    private func finishResizingWindow(translation: CGSize) {
        resizeWindow(translation: translation)
        let startFrame = resizeStartFrame ?? window?.frame ?? .zero
        let size = clampedSize(startFrame: startFrame, translation: translation)
        store.resizeNote(noteID, to: size)
        saveWindowPosition()
        resizeStartFrame = nil
    }

    private func clampedSize(startFrame: NSRect, translation: CGSize) -> NoteSize {
        NoteSize(
            width: min(
                max(startFrame.width + translation.width, DesignTokens.minimumNoteSize.width),
                DesignTokens.maximumNoteSize.width
            ),
            height: min(
                max(startFrame.height + translation.height, DesignTokens.minimumNoteSize.height),
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

    /// Closing only hides this window; the memo comes back with 메모 보기.
    private func closeCard() {
        NoteWindowCoordinator.shared.remove(noteID)
        dismissWindow(value: noteID)
    }

    private func moveToTrash(_ note: StickyNote) {
        guard !isMovingToTrash else { return }

        withAnimation(.easeInOut(duration: 0.32)) {
            isMovingToTrash = true
        }

        // The paper is SwiftUI, the glass behind it is the window; fading the window takes both
        // away together instead of leaving the backdrop on screen after the card is gone.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            window?.animator().alphaValue = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            store.moveNoteToTrash(note.id)
            closeCard()
        }
    }
}

private struct NoteWindowConfigurator: NSViewRepresentable {
    let note: StickyNote
    let windowTitle: String
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
            window.title = windowTitle
            guard !coordinator.didConfigure else { return }
            coordinator.didConfigure = true

            // A window can be recycled for another note after a delete faded this one out.
            window.alphaValue = 1
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
            window.moveOnScreenIfNeeded()
        }
    }

    final class Coordinator {
        var didConfigure = false
    }
}

extension NSWindow {
    /// A note placed while a second display was attached keeps that position after the display
    /// is gone, which opens the window where nobody can see or reach it.
    func moveOnScreenIfNeeded() {
        let screens = NSScreen.screens
        guard !screens.contains(where: { $0.visibleFrame.contains(frame) }) else { return }

        // Clamp into whichever screen already shows most of the card, so a card living on a
        // second display does not jump to the main one.
        let shownArea: (NSScreen) -> CGFloat = { screen in
            let shown = screen.visibleFrame.intersection(self.frame)
            return shown.width * shown.height
        }

        guard
            let visible = (screens.max { shownArea($0) < shownArea($1) } ?? NSScreen.main)?.visibleFrame
        else { return }

        setFrameOrigin(
            NSPoint(
                x: min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width)),
                y: min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
            )
        )
    }
}
