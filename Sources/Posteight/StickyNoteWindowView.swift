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
    @State private var showsDeleteConfirmation = false
    @State private var pendingDeleteTabID: UUID?
    @State private var isCardHovered = false
    @State private var editingTabID: UUID?
    @State private var hoveredTabID: UUID?
    @State private var lastMergeAttempt = Date.distantPast

    var body: some View {
        Group {
            if let note = store.notes.first(where: { $0.id == noteID }),
               let selectedTab = note.selectedTab {
                noteWindow(note, selectedTab: selectedTab)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        discardCard()
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
                    onDelete: requestDeleteSelectedTab,
                    isPencilCaseOpen: $isPencilCaseOpen
                )
                .id(selectedTab.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(MemoCardShape())

            MemoCardSheen()
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
        .onAppear {
            // SwiftUI can retain this scene after dismissal and reuse it on restore.
            isMovingToTrash = false
            window?.alphaValue = 1
        }
        .onHover { isCardHovered = $0 }
        .environment(\.colorScheme, .light)
        .background {
            NoteWindowConfigurator(
                note: note,
                windowTitle: selectedTab.title,
                onEscape: closeCard,
                onDelete: requestDeleteSelectedTab,
                onMoveEnded: mergeAtDropLocation,
                onAddTab: {
                    editingTabID = nil
                    _ = store.addTab(to: noteID, language: settings.language)
                }
            ) { configuredWindow in
                NoteWindowCoordinator.shared.register(configuredWindow, for: noteID)
                if window !== configuredWindow {
                    window = configuredWindow
                }
            }
        }
        .alert(L("현재 탭을 삭제할까요?"), isPresented: $showsDeleteConfirmation) {
            Button(L("취소"), role: .cancel) { pendingDeleteTabID = nil }
            Button(L("확인"), role: .destructive) { confirmDeleteTab() }
        } message: {
            Text(L("삭제한 탭은 휴지통에서 복구할 수 있어요."))
        }
        .environment(\.editingStore, store)
        .onChange(of: settings.keepsNotesOnTop) { _, _ in
            window?.level = settings.noteWindowLevel
        }
        .onChange(of: settings.hidesNotesFromScreenCapture) { _, _ in
            window?.sharingType = settings.noteWindowSharingType
        }
    }

    private func memoTabBar(note: StickyNote, selectedTab: MemoTab) -> some View {
        GeometryReader { geometry in
            let controlsWidth = MemoSurfaceMetrics.trailingControlsWidth
            let addButtonWidth = MemoSurfaceMetrics.addTabButtonWidth
            let availableTabWidth = max(0, geometry.size.width - controlsWidth - addButtonWidth)
            // Once tabs reach their maximum width, spare space belongs after the add button.
            let occupiedTabWidth = min(
                availableTabWidth,
                CGFloat(note.tabs.count) * MemoSurfaceMetrics.maximumTabWidth
            )

            HStack(alignment: .bottom, spacing: 0) {
                memoTabs(note: note, selectedTab: selectedTab, availableWidth: occupiedTabWidth)
                    .frame(width: occupiedTabWidth)

                let canAddTab = note.tabs.count < MemoSurfaceMetrics.maximumTabCount

                Button {
                    editingTabID = nil
                    _ = store.addTab(to: note.id, language: settings.language)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: addButtonWidth, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canAddTab)
                .foregroundStyle(Color.black.opacity(canAddTab ? 0.48 : 0.18))
                .help(canAddTab ? L("이 메모에 새 탭 추가") : Lf("탭은 이 메모에 최대 %d개까지 둘 수 있어요", MemoSurfaceMetrics.maximumTabCount))
                .padding(.bottom, 3)

                Spacer(minLength: 0)

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
        let tabWidth = min(MemoSurfaceMetrics.maximumTabWidth, max(MemoSurfaceMetrics.minimumTabWidth, dividedWidth))

        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 0) {
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
                .frame(height: MemoSurfaceMetrics.tabBarHeight, alignment: .bottom)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedTab.id, initial: true) { _, id in
                proxy.scrollTo(id)
            }
            .onChange(of: availableWidth) { _, _ in
                proxy.scrollTo(selectedTab.id)
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
        let isHovered = hoveredTabID == tab.id
        let showsClose = editingTabID != tab.id && (isSelected || isHovered)
        let onHover: (Bool) -> Void = { hovering in
            hoveredTabID = hovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
        }

        if isSelected {
            // The close button is a sibling of the rename button, not nested inside its label —
            // a button inside another button's label fights it for the tap instead of the two
            // splitting the tab's area by where each one actually is.
            ZStack(alignment: .trailing) {
                ZStack {
                    memoTabSurface(note, isSelected: true)

                    if editingTabID == tab.id {
                        // Bound straight to the store, the way an item title is. A local draft
                        // loses the edit whenever the commit is triggered by another control:
                        // AppKit resigns first responder on mouseDown and the field's write is
                        // deferred one hop, so the button's action would read a stale draft.
                        PlainEditableTextField(
                            text: Binding(
                                get: { store.tabName(noteID: note.id, tabID: tab.id) ?? tab.name },
                                set: { store.updateTabName(noteID: note.id, tabID: tab.id, name: $0) }
                            ),
                            placeholder: tab.name,
                            fontSize: 10,
                            fontWeight: .semibold,
                            textOpacity: 0.68,
                            isFocused: true,
                            onEditingChanged: { isEditing in
                                if !isEditing, editingTabID == tab.id {
                                    editingTabID = nil
                                }
                            },
                            onSubmit: {
                                editingTabID = nil
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 18)
                        .padding(.horizontal, horizontalPadding)
                    } else {
                        Button {
                            beginEditing(tab)
                        } label: {
                            tabLabel(
                                note: note,
                                tab: tab,
                                showsSticker: showsSticker,
                                isSelected: true,
                                reservesCloseSpace: showsClose
                            )
                            .padding(.horizontal, horizontalPadding)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if showsClose {
                    tabCloseButton(note: note, tab: tab)
                        .padding(.trailing, horizontalPadding)
                }
            }
            .frame(width: width, height: MemoSurfaceMetrics.activeTabHeight)
            .clipped()
            .help(L("현재 탭 — 다시 클릭하면 이름을 수정할 수 있어요"))
            .accessibilityAddTraits(.isSelected)
            .onHover(perform: onHover)
        } else {
            ZStack(alignment: .trailing) {
                Button {
                    editingTabID = nil
                    withAnimation(.easeOut(duration: 0.16)) {
                        store.selectTab(noteID: note.id, tabID: tab.id)
                    }
                } label: {
                    ZStack {
                        memoTabSurface(note, isSelected: false)

                        tabLabel(
                            note: note,
                            tab: tab,
                            showsSticker: showsSticker,
                            isSelected: false,
                            reservesCloseSpace: showsClose
                        )
                        .padding(.horizontal, horizontalPadding)
                    }
                }
                .buttonStyle(.plain)

                if showsClose {
                    tabCloseButton(note: note, tab: tab)
                        .padding(.trailing, horizontalPadding)
                }
            }
            .frame(width: width, height: MemoSurfaceMetrics.inactiveTabHeight)
            .contentShape(MemoTabShape())
            .help(Lf("%@ 탭으로 이동", tab.name))
            .padding(.bottom, 3)
            .clipped()
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 0.5, height: 14)
                    .padding(.bottom, 8)
            }
            .onHover(perform: onHover)
        }
    }

    private func tabCloseButton(note: StickyNote, tab: MemoTab) -> some View {
        // The last tab has nowhere to go — closing it hides the card instead of trashing
        // anything, so it must not promise the trash.
        let isLastTab = note.tabs.count <= 1

        return Button {
            closeTab(note: note, tab: tab)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                // Keep the glyph quiet, but do not make the pointer hunt for its thin strokes.
                .frame(width: 18, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(hex: note.penHex).opacity(0.6))
        .help(isLastTab
            ? L("닫기 — 메모는 그대로 있어요")
            : L("이 탭 닫기 — 휴지통에서 복구할 수 있어요"))
    }

    private func tabLabel(
        note: StickyNote,
        tab: MemoTab,
        showsSticker: Bool,
        isSelected: Bool,
        reservesCloseSpace: Bool
    ) -> some View {
        HStack(spacing: showsSticker ? 6 : 0) {
            if showsSticker {
                ZStack {
                    Image(systemName: tab.stickerSymbol)
                        .font(.system(size: isSelected ? 10 : 9, weight: .semibold))

                    if isSelected {
                        WindowMoveHandle(onDragEnded: saveWindowPosition, onDragCompleted: mergeAtDropLocation)
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
        // Room for the close button sitting on top, so the truncated name doesn't run under it.
        .padding(.trailing, reservesCloseSpace ? 18 : 0)
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
    }

    private var tabBarControls: some View {
        HStack(spacing: 0) {
            Button {
                isPencilCaseOpen.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .help(L("메모 꾸미기"))

            Button {
                closeCard()
            } label: {
                Image(systemName: "xmark")
                    // The visible x stays small; its entire 28×32pt cell closes the memo.
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .help(L("닫기 — 메모는 그대로 있어요"))
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

    /// 저장하는 쪽과 같은 식을 쓴다. 끄는 동안의 창 크기와 저장되는 크기가 갈리면 놓는 순간
    /// 창이 한 번 튄다.
    private func clampedSize(startFrame: NSRect, translation: CGSize) -> NoteSize {
        PosteightStore.clamped(
            NoteSize(width: startFrame.width + translation.width,
                     height: startFrame.height + translation.height),
            within: window?.screen?.visibleFrame
        )
    }

    private func saveWindowPosition() {
        guard let position = window?.notePosition else { return }
        store.updateNotePosition(noteID, position: position)
    }

    /// The tab's own × closes just that tab — unless it is the only one left, in which case a
    /// note with zero tabs doesn't exist in this model, so it falls back to the card's own close.
    /// Same weight as that close, too: the tab lands in 휴지통, not gone, so there is no separate
    /// "are you sure" to click through first.
    private func closeTab(note: StickyNote, tab: MemoTab) {
        guard note.tabs.count > 1 else {
            closeCard()
            return
        }

        store.moveTabToTrash(noteID: note.id, tabID: tab.id)
    }

    private func requestDeleteSelectedTab() {
        guard let note = store.notes.first(where: { $0.id == noteID }),
              let tab = note.selectedTab else { return }
        pendingDeleteTabID = tab.id
        showsDeleteConfirmation = true
    }

    private func confirmDeleteTab() {
        defer { pendingDeleteTabID = nil }
        guard let tabID = pendingDeleteTabID,
              let note = store.notes.first(where: { $0.id == noteID }),
              note.tabs.contains(where: { $0.id == tabID }) else { return }
        editingTabID = nil
        if note.tabs.count == 1 {
            moveToTrash(note)
        } else {
            store.moveTabToTrash(noteID: noteID, tabID: tabID)
        }
    }

    private func mergeAtDropLocation() {
        guard store.notes.contains(where: { $0.id == noteID }),
              Date().timeIntervalSince(lastMergeAttempt) > 0.3 else { return }
        lastMergeAttempt = Date()
        saveWindowPosition()
        guard let targetID = NoteWindowCoordinator.shared.dropTarget(at: NSEvent.mouseLocation, excluding: noteID) else { return }
        if store.mergeNotes(from: noteID, into: targetID) {
            discardCard()
        } else {
            let alert = NSAlert()
            alert.messageText = Lf("탭은 이 메모에 최대 %d개까지 둘 수 있어요", MemoSurfaceMetrics.maximumTabCount)
            if let window {
                // The sheet is its own AppKit window, so the card's exclusion does not cover it.
                alert.window.sharingType = AppSettings.shared.noteWindowSharingType
                alert.beginSheetModal(for: window)
            }
        }
    }

    private func closeCard() {
        store.recordClosedWindow(noteID)
        NoteWindowCoordinator.shared.hide(noteID)
    }

    /// Removing the memo itself also tears down its SwiftUI scene; unlike a normal close, there
    /// is no card left for 메모 보기 to restore.
    private func discardCard() {
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
            discardCard()
            // Dismissal does not guarantee destruction of the scene or its state.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { isMovingToTrash = false }
            window?.alphaValue = 1
        }
    }
}


private struct NoteWindowConfigurator: NSViewRepresentable {
    let note: StickyNote
    let windowTitle: String
    let onEscape: () -> Void
    let onDelete: () -> Void
    let onMoveEnded: () -> Void
    let onAddTab: () -> Void
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
            coordinator.onEscape = onEscape
            coordinator.onAddTab = onAddTab
            coordinator.onDelete = onDelete
            coordinator.onMoveEnded = onMoveEnded
            coordinator.window = window
            onWindowAvailable(window)
            window.title = windowTitle
            guard !coordinator.didConfigure else { return }
            coordinator.didConfigure = true
            coordinator.installEscapeMonitor()

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
            window.sharingType = AppSettings.shared.noteWindowSharingType
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
            // 화면에 안 들어가는 크기로 열면 손잡이가 화면 밖이라 줄일 수 없다. 저장값은 건드리지
            // 않는다 — 큰 화면으로 돌아가면 사용자가 고른 크기가 그대로 살아난다.
            let fitted = PosteightStore.clamped(
                note.size, within: NSScreen.holding(note.position)?.visibleFrame)
            window.setContentSize(NSSize(width: fitted.width, height: fitted.height))

            window.placeNote(at: note.position)
            window.moveOnScreenIfNeeded()
        }
    }

    @MainActor
    final class Coordinator {
        var didConfigure = false
        weak var window: NSWindow?
        var onEscape: (() -> Void)?
        var onAddTab: (() -> Void)?
        var onDelete: (() -> Void)?
        var onMoveEnded: (() -> Void)?
        private var dragStartFrame: NSRect?
        nonisolated(unsafe) private var dragMonitor: Any?
        nonisolated(unsafe) private var escapeMonitor: Any?

        func installEscapeMonitor() {
            guard escapeMonitor == nil else { return }

            dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                guard let self else { return event }
                if event.type == .leftMouseDown {
                    self.dragStartFrame = event.window === self.window ? self.window?.frame : nil
                } else if let start = self.dragStartFrame {
                    self.dragStartFrame = nil
                    if let frame = self.window?.frame, frame.origin != start.origin, frame.size == start.size {
                        self.onMoveEnded?()
                    }
                }
                return event
            }
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard
                    let self,
                    event.window === self.window
                else { return event }

                switch NoteKeyboardShortcut(event: event) {
                case .addTab:
                    self.onAddTab?()
                    return nil
                case .deleteTab:
                    self.onDelete?()
                    return nil
                case .close:
                    self.onEscape?()
                    return nil
                case .undo, .redo:
                    // Document history is routed once at app level, including hidden windows.
                    return event
                case nil:
                    break
                }
                return event
            }
        }

        deinit {
            if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
            }
        }
    }
}

extension NSScreen {
    /// 메모 위치를 재는 기준. `note.position` 은 이 프레임의 좌상단에서 잰 값이다.
    ///
    /// 여기에 `NSScreen.main` 이나 `visibleFrame` 을 쓰면 안 된다. `NSScreen.main` 은 주
    /// 디스플레이가 아니라 **키보드 포커스를 가진 창이 있는 화면**이고, `visibleFrame` 은 Dock 과
    /// 메뉴 막대를 따라 움직인다. 둘 중 하나라도 기준이 되면 저장한 좌표가 절대 위치가 아니라
    /// "그때 그 화면의 여백 기준 오프셋" 이 되어, 기준이 달라진 다음 실행에 메모가 그 차이만큼
    /// 밀린다 — Dock 을 옆으로 옮기면 Dock 폭만큼, 화면이 두 대면 아예 다른 모니터로.
    ///
    /// 메뉴 막대가 있는 화면의 `frame` 은 원점이 늘 (0, 0) 이고 여백을 타지 않는다.
    ///
    /// 디스플레이가 전부 떨어진 순간에는 기준이 아예 없다. 예전에는 그때 `.zero` 로 떨어졌는데,
    /// 그 값으로 위치를 적으면 `y` 가 통째로 음수가 되어 다음 실행에 메모가 화면 위로 튀어나간다.
    /// 기준이 없다는 것을 타입으로 말하게 해서, 부르는 쪽이 적지 않기로 고르게 한다.
    static var noteAnchor: NSRect? {
        screens.first?.frame ?? main?.frame
    }

    /// 새 메모가 뜰 화면의 좌상단을 메모 좌표로 돌려준다. 주 디스플레이면 (0, 0) 이라 기존
    /// 동작 그대로다.
    ///
    /// 쓰고 있던 메모 창이 있으면 그 화면, 없으면 마우스가 있는 화면이다. 키보드로 ⌘N 을 누르면
    /// 쓰던 메모 옆에 뜨고, 메뉴 막대에서 누르면 그 막대가 있는 화면에 뜬다.
    ///
    /// `NSScreen.main` 은 여기서도 쓸 수 없다. 이 앱의 창이 아니라 **아무 앱이든** 포커스를 가진
    /// 창이 있는 화면이라, 이 앱이 활성이 아닌 순간에 읽으면 남의 창을 따라간다.
    /// `NSApp.keyWindow` 는 이 앱의 창만 본다 — 그 대신 `NSApp` 을 읽느라 이 하나만 MainActor 다.
    @MainActor
    static var noteSpawnOrigin: NotePoint {
        let target = NSApp.keyWindow?.screen
            ?? screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? screens.first
        guard let anchor = noteAnchor, let frame = target?.frame else { return NotePoint(x: 0, y: 0) }
        return NotePoint(x: frame.minX - anchor.minX, y: anchor.maxY - frame.maxY)
    }

    /// 이 자리의 메모가 놓일 화면. 중심이 들어가는 디스플레이가 없으면 주 디스플레이다.
    static func holding(_ position: NotePoint) -> NSScreen? {
        guard let anchor = noteAnchor else { return nil }
        let center = NSPoint(x: anchor.minX + position.x, y: anchor.maxY - position.y)
        return screens.first { $0.frame.contains(center) } ?? screens.first
    }

    /// 메모가 아직 손에 닿는가. 창 중심이 어느 디스플레이 안에 있으면 닿는다.
    ///
    /// 예전 판정은 "어느 한 화면의 `visibleFrame` 이 창을 통째로 품는가" 였고 두 가지가 걸렸다.
    /// 모니터 두 대 경계에 걸쳐 둔 메모는 어느 쪽도 통째로 품지 못해 실행할 때마다 한쪽으로
    /// 끌려갔다. 그리고 `visibleFrame` 은 Dock 과 메뉴 막대를 뺀 넓이라, Dock 에 걸친 메모가
    /// 실행할 때마다 Dock 높이만큼 위로 당겨졌다 — 당겨진 자리는 저장되지 않으므로 Dock 을
    /// 자동 숨김으로 바꾸면 같은 메모가 또 다른 자리에 떴다.
    ///
    /// 그래서 기준이 `visibleFrame` 이 아니라 `frame` 이다. Dock 아래나 메뉴 막대 밑에 창을 두는
    /// 것은 macOS 가 허락하는 배치이고, 무엇보다 사용자가 끌어다 놓은 자리다. 구해 낼 대상은
    /// 가려진 창이 아니라 **이제 없는 화면에 남은 창** 하나뿐이다.
    nonisolated static func showsNote(_ frame: NSRect, on displays: [NSRect]) -> Bool {
        displays.contains { $0.contains(NSPoint(x: frame.midX, y: frame.midY)) }
    }
}

extension NSWindow {
    /// 창의 지금 자리를 메모 좌표로 옮긴다. 기준이 없으면 `nil` — 적을 수 있는 값이 아니다.
    var notePosition: NotePoint? {
        guard let anchor = NSScreen.noteAnchor else { return nil }
        return NotePoint(x: frame.midX - anchor.minX, y: anchor.maxY - frame.midY)
    }

    /// `notePosition` 의 역. 저장하는 식과 복원하는 식이 갈리지 않게 나란히 둔다.
    func placeNote(at position: NotePoint) {
        guard let anchor = NSScreen.noteAnchor else { return }
        // 정수로 떨어뜨린다. 자리를 중심으로 저장하므로 폭이 홀수면 원점이 .5 로 남고, 배율이
        // 1x 인 외장 모니터에서 그 반 픽셀만큼 글자가 번진다.
        setFrameOrigin(
            NSPoint(
                x: (anchor.minX + position.x - frame.width * 0.5).rounded(),
                y: (anchor.maxY - position.y - frame.height * 0.5).rounded()
            )
        )
    }

    /// A note placed while a second display was attached keeps that position after the display
    /// is gone, which opens the window where nobody can see or reach it.
    func moveOnScreenIfNeeded() {
        let screens = NSScreen.screens
        guard !NSScreen.showsNote(frame, on: screens.map(\.frame)) else { return }

        // 구해 내는 자리는 `visibleFrame` 이다. 판정과 기준이 다른 것은 일부러다 — 사용자가 둔
        // 자리는 Dock 아래라도 그대로 두지만, 앱이 대신 옮길 때는 가리는 것 없는 자리로 옮긴다.
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
