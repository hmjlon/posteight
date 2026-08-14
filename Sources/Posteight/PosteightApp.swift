import SwiftUI

@main
struct PosteightApp: App {
    @StateObject private var store = PosteightStore()

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .environmentObject(store)
                .fixedSize()
                .background(WorkspaceWindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sticky Note") {
                    store.addNote()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        WindowGroup("Posteight", for: UUID.self) { $noteID in
            if let noteID {
                StickyNoteWindowView(noteID: noteID)
                    .environmentObject(store)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: DesignTokens.defaultNoteSize.width,
            height: DesignTokens.defaultNoteSize.height
        )
    }
}

private struct WorkspaceWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.title = "Posteight"
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
