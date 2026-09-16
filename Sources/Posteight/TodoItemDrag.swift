import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct TodoItemDrag: Codable, Transferable {
    let noteID: UUID
    let tabID: UUID
    let itemID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.younjiyoung.posteight.todo-item"))
    }
}

struct TodoItemDragHandle: NSViewRepresentable {
    let item: TodoItemDrag
    let color: NSColor
    let isVisible: Bool

    func makeNSView(context: Context) -> NativeHandle {
        NativeHandle()
    }

    func updateNSView(_ view: NativeHandle, context: Context) {
        view.item = item
        view.color = color
        view.isVisible = isVisible
        view.needsDisplay = true
    }

    final class NativeHandle: NSView, NSDraggingSource {
        var item: TodoItemDrag?
        var color = NSColor.labelColor
        var isVisible = false
        private var isHovered = false
        private var trackingArea: NSTrackingArea?

        override var mouseDownCanMoveWindow: Bool {
            // The note window moves from its tab handle. This control owns its mouse sequence
            // so dragging a task can never fall through to the window background drag.
            false
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            // 기한을 준다. `until: .distantFuture` 는 다음 드래그나 마우스 업이 오지 않는 경로가
            // 하나라도 생기면 메인 스레드를 그 자리에서 영원히 붙잡고, 그때는 앱 전체가 굳어
            // 복구할 방법이 없다.
            //
            // 기한이 지나 빠져나가도 드래그를 잃지는 않는다. 이 메서드가 돌아가면 AppKit 이
            // 평소대로 `mouseDragged` 를 이 뷰에 보내고, 그쪽도 `beginTaskDrag` 를 부른다.
            // 그래서 손을 짚은 채 한참 생각하다 끄는 사용자도 그대로 끌 수 있다.
            //
            // 이 루프가 `leftMouseUp` 을 직접 dequeue 하므로 `NoteWindowConfigurator` 의 로컬
            // 마우스 모니터는 그 업을 보지 못한다. 지금은 다음 `leftMouseDown` 이
            // `dragStartFrame` 을 덮어써서 무해하지만, 그쪽 로직을 고칠 때 알고 있어야 한다.
            while let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: Date().addingTimeInterval(1),
                inMode: .eventTracking,
                dequeue: true
            ) {
                guard next.type == .leftMouseDragged else { return }
                beginTaskDrag(with: next)
                return
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard isVisible || isHovered else { return }
            Self.drawGrip(color: color)
        }

        /// 손잡이 글리프. 드래그 이미지도 이걸 쓴다 — 뷰의 `isHovered` 를 읽지 않아야
        /// 래스터화 시점이 언제든 같은 그림이 나온다.
        nonisolated private static func drawGrip(color: NSColor) {
            color.withAlphaComponent(0.65).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.lineCapStyle = .round
            for y in [8.0, 12.0, 16.0] {
                path.move(to: NSPoint(x: 3, y: y))
                path.line(to: NSPoint(x: 13, y: y))
            }
            path.stroke()
        }

        override func mouseDragged(with event: NSEvent) {
            beginTaskDrag(with: event)
        }

        private func beginTaskDrag(with event: NSEvent) {
            guard let item, let data = try? JSONEncoder().encode(item) else { return }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(data, forType: .init("com.younjiyoung.posteight.todo-item"))
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            // `lockFocus()` 는 주 디스플레이 배율로 굽는다. 배율이 다른 화면이 섞여 있으면
            // 한쪽에서 흐려진다 — `MenuBarProgressCard` 가 이미 같은 함정을 겪었다
            // (`FoldedCardSurface` 의 `render`). 그리는 시점의 컨텍스트 배율을 따라가는
            // drawing handler 로 바꾸면 화면을 고를 필요 자체가 없어진다.
            let color = self.color
            let image = NSImage(size: bounds.size, flipped: false) { _ in
                NativeHandle.drawGrip(color: color)
                return true
            }
            draggingItem.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            isHovered = true
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            needsDisplay = true
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }
    }
}

/// Rows accept insertion on either side; the empty tail and tab headers append.
struct TodoItemDropTarget: ViewModifier {
    @EnvironmentObject private var store: PosteightStore
    let noteID: UUID
    let tabID: UUID
    var beforeID: UUID? = nil
    var selectsTab = false
    @State private var isTargeted = false
    @State private var height: CGFloat = 28
    @State private var insertAfter = false

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geometry in
                Color.clear.onAppear { height = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, value in height = value }
            })
            .contentShape(Rectangle())
            .overlay(alignment: insertAfter && beforeID != nil ? .bottom : .top) {
                if isTargeted {
                    Rectangle().fill(Color.accentColor).frame(height: 2)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: ["com.younjiyoung.posteight.todo-item"], delegate: TaskDropDelegate(
                store: store, noteID: noteID, tabID: tabID, beforeID: beforeID,
                selectsTab: selectsTab, height: height, isTargeted: $isTargeted, insertAfter: $insertAfter
            ))
    }
}

private struct TaskDropDelegate: DropDelegate {
    let store: PosteightStore
    let noteID: UUID
    let tabID: UUID
    let beforeID: UUID?
    let selectsTab: Bool
    let height: CGFloat
    @Binding var isTargeted: Bool
    @Binding var insertAfter: Bool
    private let type = "com.younjiyoung.posteight.todo-item"

    /// 받을 수 없는 드롭에는 삽입선을 그리지 않는다. `false` 를 돌려주면 SwiftUI 가
    /// `dropEntered` 를 부르지 않아 `isTargeted` 가 켜지지 않는다.
    ///
    /// 끌고 오는 항목이 무엇인지는 드래그 페이스트보드에서 바로 읽는다. 이 자리에서
    /// `loadDataRepresentation` 은 비동기라 늦고, 드래그는 앱 안에서만 시작되므로
    /// (`draggingSession(_:sourceOperationMaskFor:)` 가 앱 밖으로는 빈 마스크를 준다)
    /// 페이스트보드에는 우리가 쓴 값만 들어 있다.
    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [type]) else { return false }
        guard let source = draggedItem else { return true }
        return store.canMoveItem(source, toNote: noteID, tab: tabID, before: beforeID)
    }

    private var draggedItem: TodoItemDrag? {
        guard let data = NSPasteboard(name: .drag).data(forType: .init(type)) else { return nil }
        return try? JSONDecoder().decode(TodoItemDrag.self, from: data)
    }

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        insertAfter = info.location.y > height / 2
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [type]).first else { return false }
        let insertAfter = info.location.y > height / 2
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
            guard let data, let item = try? JSONDecoder().decode(TodoItemDrag.self, from: data) else { return }
            Task { @MainActor in
                var insertionID = beforeID
                if insertAfter, let beforeID,
                   let items = store.notes.first(where: { $0.id == noteID })?.tabs.first(where: { $0.id == tabID })?.items,
                   let index = items.firstIndex(where: { $0.id == beforeID }) {
                    insertionID = items.dropFirst(index + 1).first?.id
                }
                let moved = store.moveItem(item, toNote: noteID, tab: tabID, before: insertionID)
                if moved && selectsTab { store.selectTab(noteID: noteID, tabID: tabID) }
            }
        }
        return true
    }
}
