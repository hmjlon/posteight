import AppKit
import SwiftUI

/// Controls the optional count beside the menu bar progress icon.
enum MenuBarCountStyle: String, CaseIterable, Identifiable {
    case remaining
    case done
    case hidden

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .remaining: L("남은 일", language: language)
        case .done: L("완료", language: language)
        case .hidden: L("표시 없음", language: language)
        }
    }
}

/// Posteight is a menu bar utility, but the Dock icon is a user choice: it makes the running
/// app switchable with the Dock and Command-Tab, at the cost of some Dock clutter.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var defaultFontSize: NoteFontSize {
        didSet { UserDefaults.standard.set(defaultFontSize.rawValue, forKey: "posteight.defaultFontSize") }
    }

    @Published var defaultFontID: String {
        didSet { UserDefaults.standard.set(defaultFontID, forKey: "posteight.defaultFontID") }
    }

    private enum Key {
        static let dockIcon = "posteight.showsDockIcon"
        static let countStyle = "posteight.menuBarCountStyle"
        static let notesOnTop = "posteight.keepsNotesOnTop"
        static let hidesFromCapture = "posteight.hidesNotesFromScreenCapture"
        static let reminderPreview = "posteight.showsReminderPreview"
        static let language = "posteight.language"
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

    /// Every string Posteight draws itself follows this. The menus macOS draws — File, Edit,
    /// Window — come from the system language and are out of reach without a bundle relaunch.
    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Key.language)
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

    /// On by default: a memo the user keeps on the desktop all day should not walk into a
    /// screen share by accident. Turning it off is for the times a memo is the thing being
    /// shown — a demo, a stream, a screenshot for documentation.
    @Published var hidesNotesFromScreenCapture: Bool {
        didSet {
            guard hidesNotesFromScreenCapture != oldValue else { return }
            UserDefaults.standard.set(hidesNotesFromScreenCapture, forKey: Key.hidesFromCapture)
        }
    }

    /// Off by default, on the same reasoning as the screen capture exclusion: a notification is
    /// drawn on the lock screen and kept in the system notification database, both outside this
    /// app's reach. No API lets an app force the preview policy, so the only control left is to
    /// keep the task's own words out of the body. Turning it on is for people who would rather
    /// read the task than unlock the Mac.
    @Published var showsReminderPreview: Bool {
        didSet {
            guard showsReminderPreview != oldValue else { return }
            UserDefaults.standard.set(showsReminderPreview, forKey: Key.reminderPreview)
        }
    }

    /// Bumped when the Dock icon is clicked, so the menu bar label can bring the card back.
    @Published private(set) var showAllNotesRequests = 0

    var noteWindowLevel: NSWindow.Level {
        keepsNotesOnTop ? .floating : .normal
    }

    var noteWindowSharingType: NSWindow.SharingType {
        hidesNotesFromScreenCapture ? .none : .readOnly
    }

    private init() {
        let defaults = UserDefaults.standard
        defaultFontSize = defaults.string(forKey: "posteight.defaultFontSize").flatMap(NoteFontSize.init(rawValue:)) ?? .medium
        defaultFontID = defaults.string(forKey: "posteight.defaultFontID") ?? "system"
        showsDockIcon = defaults.object(forKey: Key.dockIcon) as? Bool ?? true
        keepsNotesOnTop = defaults.object(forKey: Key.notesOnTop) as? Bool ?? true
        hidesNotesFromScreenCapture = defaults.object(forKey: Key.hidesFromCapture) as? Bool ?? true
        showsReminderPreview = defaults.object(forKey: Key.reminderPreview) as? Bool ?? false
        menuBarCountStyle = (defaults.string(forKey: Key.countStyle)
            .flatMap(MenuBarCountStyle.init(rawValue:))) ?? .remaining
        language = (defaults.string(forKey: Key.language)
            .flatMap(AppLanguage.init(rawValue:))) ?? .system
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
