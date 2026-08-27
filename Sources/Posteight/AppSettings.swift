import AppKit
import SwiftUI

/// What the menu bar icon counts. Both forms show progress against the day's total.
enum MenuBarCountStyle: String, CaseIterable, Identifiable {
    case remaining
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining: "남은 일"
        case .done: "완료"
        }
    }
}

/// Posteight is a menu bar utility, but the Dock icon is a user choice: it makes the running
/// app switchable with the Dock and Command-Tab, at the cost of some Dock clutter.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let dockIcon = "posteight.showsDockIcon"
        static let countStyle = "posteight.menuBarCountStyle"
        static let notesOnTop = "posteight.keepsNotesOnTop"
    }

    @Published var showsDockIcon: Bool {
        didSet {
            guard showsDockIcon != oldValue else { return }
            UserDefaults.standard.set(showsDockIcon, forKey: Key.dockIcon)
            applyActivationPolicy()
        }
    }

    @Published var menuBarCountStyle: MenuBarCountStyle {
        didSet {
            guard menuBarCountStyle != oldValue else { return }
            UserDefaults.standard.set(menuBarCountStyle.rawValue, forKey: Key.countStyle)
        }
    }

    /// Notes float above other apps by default. Turning this off lets them fall behind whatever
    /// the user is working in, which is the quieter choice during long focused work.
    @Published var keepsNotesOnTop: Bool {
        didSet {
            guard keepsNotesOnTop != oldValue else { return }
            UserDefaults.standard.set(keepsNotesOnTop, forKey: Key.notesOnTop)
        }
    }

    /// Bumped when the Dock icon is clicked, so the menu bar label can bring every note back.
    @Published private(set) var showAllNotesRequests = 0

    var noteWindowLevel: NSWindow.Level {
        keepsNotesOnTop ? .floating : .normal
    }

    private init() {
        let defaults = UserDefaults.standard
        showsDockIcon = defaults.object(forKey: Key.dockIcon) as? Bool ?? true
        keepsNotesOnTop = defaults.object(forKey: Key.notesOnTop) as? Bool ?? true
        menuBarCountStyle = (defaults.string(forKey: Key.countStyle)
            .flatMap(MenuBarCountStyle.init(rawValue:))) ?? .remaining
    }

    /// `swift build` produces an unbundled binary, where `LSUIElement` from `Packaging/Info.plist`
    /// never applies and the process starts as `.prohibited` — no windows, no status item. Setting
    /// the policy in code keeps both build paths out of that state.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)

        if showsDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func requestShowAllNotes() {
        showAllNotesRequests += 1
    }
}
