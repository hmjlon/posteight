import AppKit
import SwiftUI
import Testing
@testable import Posteight

extension AppKitEditingTests {
    /// 창 메뉴의 타일 배치나 창 관리 앱이 옮긴 것은 마우스로 끈 것이 아니라서 `onMoveEnded` 가 뜨지
    /// 않는다. 탭이 몇 개든 그 자리도 적혀야 다음 실행에 같은 자리에 뜬다.
    @Suite
    @MainActor
    struct NoteWindowMoveTests {
        @Test(arguments: [1, 2])
        func movingTheWindowSavesItsPosition(tabCount: Int) async throws {
            _ = NSApplication.shared
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = PosteightStore(directory: directory)
            let noteID = store.addNote()
            for _ in 1..<tabCount { try #require(store.addTab(to: noteID) != nil) }
            func saved() -> NotePoint? { store.notes.first { $0.id == noteID }?.position }
            let start = try #require(saved())

            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 260),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: StickyNoteWindowView(noteID: noteID).environmentObject(store))
            window.orderFront(nil)
            defer {
                window.orderOut(nil)
                window.contentView = nil
                NoteWindowCoordinator.shared.remove(noteID)
            }

            // 창이 저장값 자리로 옮겨질 때까지 기다린다. 자리는 정수로 떨어뜨려 놓으므로 반 점까지 어긋난다.
            let placed = try await waitForEditorState {
                guard let position = window.notePosition else { return false }
                return abs(position.x - start.x) <= 0.5 && abs(position.y - start.y) <= 0.5
            }
            try #require(placed)

            window.setFrameOrigin(NSPoint(x: window.frame.minX + 40, y: window.frame.minY - 30))
            let target = try #require(window.notePosition)
            let didSave = try await waitForEditorState { saved() == target }
            #expect(didSave)
        }
    }
}
