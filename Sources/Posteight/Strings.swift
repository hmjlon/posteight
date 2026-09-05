import Foundation

/// What the user picked in Settings. `.system` follows the Mac's own language list, so a fresh
/// install reads in the language the rest of the machine already uses.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case korean
    case english

    var id: String { rawValue }

    /// Never `.system` — the concrete language every lookup is answered in.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        return Self.systemLanguage(
            override: ProcessInfo.processInfo.environment[Self.systemLanguageOverride],
            preferred: Locale.preferredLanguages.first
        )
    }

    /// CI runs on an English machine while this project is developed on a Korean one, so a
    /// locale bug passes locally and only fails after a push. Set this to reproduce the runner:
    ///
    ///     POSTEIGHT_SYSTEM_LANGUAGE=en swift test
    ///
    static let systemLanguageOverride = "POSTEIGHT_SYSTEM_LANGUAGE"

    /// Pure on purpose. A test that set the real process environment would leak into every other
    /// test running beside it, so both inputs are passed in instead. An unreadable tag falls
    /// through to the next candidate rather than forcing a language.
    static func systemLanguage(override: String?, preferred: String?) -> AppLanguage {
        for tag in [override, preferred].compactMap(\.self).map({ $0.lowercased() }) {
            if tag.hasPrefix("ko") { return .korean }
            if tag.hasPrefix("en") { return .english }
        }
        return .english
    }

    /// Each option is written in its own language, so the list reads the same whichever one is on.
    /// The reading language is passed in rather than read from `AppSettings`: a view builder that
    /// reaches for a singleton hides the dependency, and SwiftUI never rebuilds on it.
    func title(in language: AppLanguage) -> String {
        switch self {
        case .system: L("시스템 설정에 따름", language: language)
        case .korean: "한국어"
        case .english: "English"
        }
    }

    /// Dates inside memo titles follow the reading language, not the system region.
    var localeIdentifier: String {
        resolved == .korean ? "ko_KR" : "en_US"
    }
}

/// Korean is the source language, so the Korean text itself is the key. A missing entry falls
/// back to that key: the worst case is a Korean string in an English window, never a crash or a
/// raw `some.dotted.token`.
///
/// ponytail: a plain dictionary, not `.lproj` resources. String Catalogs cannot switch language
/// without relaunching, and resource bundles would have to be wired into both the SwiftPM and the
/// Xcode build paths — two places to drift. Move to `.lproj` when a third language or a
/// translator shows up.
private let englishStrings: [String: String] = [
    // AppSettings
    "남은 일": "Remaining",
    "완료": "Done",

    // DailyLogPreviewView
    "오늘 기록": "Today's Log",
    "Markdown 복사": "Copy Markdown",
    "Notion 기록이 켜진 메모만 정리됩니다.": "Only memos with the Notion log turned on are collected here.",

    // MenuBarPanelView
    "새 메모": "New Memo",
    "메모 보기": "Show Memos",
    "모든 메모 숨기기": "Hide All Memos",
    "오늘 기록 미리보기": "Preview Today's Log",
    "휴지통": "Trash",
    "설정…": "Settings…",
    "Posteight 종료": "Quit Posteight",
    "할 일 없음": "No tasks",
    "남은 일 %ld개": "%ld remaining",
    "완료 %ld개": "%ld done",
    "모두 완료": "All done",

    // Models — pen styles
    "연필": "Pencil",
    "볼펜": "Ballpoint",
    "형광펜": "Highlighter",

    // Models — stickers
    "업무": "Work",
    "학업": "Study",
    "회의": "Meeting",
    "개발": "Dev",
    "마감": "Deadline",
    "긴급": "Urgent",
    "아이디어": "Idea",
    "개인": "Personal",
    "건강": "Health",
    "장보기": "Shopping",

    // PencilCaseView
    "필통": "Pencil Case",
    "Notion 기록": "Notion log",
    "종이": "Paper",
    "펜": "Pen",
    "직접": "Custom",
    "종이 색 직접 선택": "Pick a paper color",
    "펜 색 직접 선택": "Pick a pen color",
    "펜촉": "Nib",
    "스티커": "Stickers",
    "탭 아이콘": "Tab Icon",
    "메모 삭제": "Delete Memo",
    "이 메모를 휴지통으로 보냅니다": "Moves this memo to the trash",

    // PosteightStore — memo tabs and the daily log
    "메모 %ld": "Memo %ld",
    "%@ 업무 기록": "%@ Work Log",
    "Notion 기록에 포함된 메모가 없습니다.": "No memos are included in the Notion log.",
    "완료한 일": "Done",
    "없음": "None",

    // PosteightStore — first-launch sample notes
    "오늘 업무": "Today's Work",
    "메모 앱 첫 화면 만들기": "Build the first screen",
    "필통에 색상과 스티커 담기": "Fill the pencil case with colors and stickers",
    "펜 줄긋기 애니메이션 확인": "Check the pen strike-through animation",
    "개인 메모": "Personal Notes",
    "점심 메뉴 정하기": "Decide what's for lunch",
    "퇴근 후 장보기": "Groceries after work",

    // SettingsModal / SettingsView
    "Posteight 설정": "Posteight Settings",
    "메뉴 막대": "Menu Bar",
    "표시 방식": "Shows",
    "미리보기": "Preview",
    "노트": "Notes",
    "노트를 항상 맨 앞에 표시": "Keep notes in front",
    "끄면 다른 앱 뒤로 밀려나서, 집중해서 일할 때 화면을 덜 가립니다.":
        "With this off, notes fall behind other apps and cover less of the screen during focused work.",
    "화면 공유와 스크린샷에서 노트 감추기": "Hide notes from screen sharing and screenshots",
    "켜 두면 화면을 공유하거나 녹화할 때, 스크린샷을 찍을 때 노트가 찍히지 않습니다. 노트를 직접 보여 주려면 끕니다.":
        "With this on, notes stay out of screen shares, recordings and screenshots. Turn it off when the notes are what you mean to show.",
    "앱": "App",
    "언어": "Language",
    "시스템 설정에 따름": "Follow system setting",
    "Posteight 안에서만 바뀝니다. macOS 가 그리는 메뉴 막대 메뉴는 시스템 언어를 따릅니다.":
        "This changes Posteight only. The menus macOS draws itself still follow the system language.",
    "Dock 아이콘 표시": "Show Dock icon",
    "끄면 메뉴 막대에서만 실행됩니다. Dock 아이콘을 누르면 모든 노트가 다시 열립니다.":
        "With this off, Posteight runs from the menu bar only. Clicking the Dock icon reopens every note.",
    "노트 저장 위치": "Notes folder",
    "폴더 열기": "Open Folder",
    "버전": "Version",
    "개발 빌드": "Development build",

    // StickyNoteView
    "할 일 추가": "Add item",
    "가로 크기 조절": "Resize width",
    "세로 크기 조절": "Resize height",
    "대각선 크기 조절": "Resize",

    // StickyNoteWindowView
    "이 메모에 새 탭 추가": "Add a tab to this memo",
    "탭은 이 메모에 최대 5개까지 둘 수 있어요": "A memo holds at most 5 tabs",
    "현재 탭 — 다시 클릭하면 이름을 수정할 수 있어요": "Current tab — click it again to rename",
    "%@ 탭으로 이동": "Switch to %@",
    "이 탭 닫기 — 휴지통에서 복구할 수 있어요": "Close this tab — you can restore it from the trash",
    "메모 꾸미기": "Customize memo",
    "닫기 — 메모는 그대로 있어요": "Close — the memo stays",

    // TodoItemRow
    "완료 취소": "Undo",
    "할 일을 입력하면 완료할 수 있어요": "Type something first, then you can check it off",
    "할 일 입력": "New item",
    "세부사항 보기": "Show details",
    "세부사항 추가": "Add details",
    "삭제": "Delete",
    "무엇을, 어떻게 하는지 적어두세요": "Jot down what it is and how to do it",
    "자동 저장": "Saved automatically",
    "⌘↩ 완료": "⌘↩ Done",
    "닫기 — 적은 내용은 이미 저장돼 있어요": "Close — what you wrote is already saved",

    // TrashView
    "비우기": "Empty",
    "휴지통이 비어 있어요": "The trash is empty",
    "메모": "Memo",
    "탭 %ld개 · 할 일 %ld개": "%ld tabs · %ld items",
    "복구": "Restore",
    "완전 삭제": "Delete permanently",
    "탭 · 할 일 %ld개": "Tab · %ld items"
]

/// The reading language, for pure code that must not reach for `AppSettings`.
func L(_ korean: String, language: AppLanguage) -> String {
    language.resolved == .korean ? korean : (englishStrings[korean] ?? korean)
}

/// The reading language currently set. Views call this one.
@MainActor
func L(_ korean: String) -> String {
    L(korean, language: AppSettings.shared.language)
}

func Lf(_ korean: String, language: AppLanguage, _ arguments: any CVarArg...) -> String {
    String(format: L(korean, language: language), arguments: arguments)
}

@MainActor
func Lf(_ korean: String, _ arguments: any CVarArg...) -> String {
    String(format: L(korean), arguments: arguments)
}

#if DEBUG
/// Test hook: every key must translate to something non-empty and actually different.
enum StringTable {
    static var englishKeys: [String] { Array(englishStrings.keys) }
    static func english(_ korean: String) -> String? { englishStrings[korean] }
}
#endif
