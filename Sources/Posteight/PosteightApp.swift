import SwiftUI

@main
struct PosteightApp: App {
    @StateObject private var store = PosteightStore()

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 620)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sticky Note") {
                    store.addNote()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.title = "Posteight"
            window.level = .floating
            window.isMovableByWindowBackground = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.setFrame(NSRect(x: 180, y: 180, width: 980, height: 700), display: true)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
