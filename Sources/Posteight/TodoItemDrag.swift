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
            while let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
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
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            draw(bounds)
            image.unlockFocus()
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

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [type]) }
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
