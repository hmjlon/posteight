import Foundation
import SwiftUI

struct StickyNote: Identifiable, Codable, Equatable {
    var id: UUID
    var stickerSymbol: String
    var paperHex: String
    var penHex: String
    var penStyle: PenStyle
    var includeInNotionLog: Bool
    var position: NotePoint
    var size: NoteSize
    var tabs: [MemoTab]
    var selectedTabID: UUID

    init(
        id: UUID = UUID(),
        stickerSymbol: String,
        paperHex: String,
        penHex: String,
        penStyle: PenStyle = .ballpoint,
        includeInNotionLog: Bool,
        position: NotePoint,
        size: NoteSize = DesignTokens.defaultNoteSize,
        tabs: [MemoTab],
        selectedTabID: UUID? = nil
    ) {
        let safeTabs = tabs.isEmpty
            ? [MemoTab(name: "메모 1", title: "", items: [TodoItem(title: "")])]  // 손상된 데이터 복구용 기본값
            : tabs

        self.id = id
        self.stickerSymbol = stickerSymbol
        self.paperHex = paperHex
        self.penHex = penHex
        self.penStyle = penStyle
        self.includeInNotionLog = includeInNotionLog
        self.position = position
        self.size = size
        self.tabs = safeTabs
        if let selectedTabID, safeTabs.contains(where: { $0.id == selectedTabID }) {
            self.selectedTabID = selectedTabID
        } else {
            self.selectedTabID = safeTabs[0].id
        }
    }

    var selectedTab: MemoTab? {
        tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    var allItems: [TodoItem] {
        tabs.flatMap(\.items)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case stickerSymbol
        case paperHex
        case penHex
        case penStyle
        case includeInNotionLog
        case position
        case size
        case tabs
        case selectedTabID
        // Read-only migration fields from the single-content note model.
        case title
        case items
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        stickerSymbol = try container.decode(String.self, forKey: .stickerSymbol)
        paperHex = try container.decode(String.self, forKey: .paperHex)
        penHex = try container.decode(String.self, forKey: .penHex)
        penStyle = try container.decodeIfPresent(PenStyle.self, forKey: .penStyle) ?? .ballpoint
        includeInNotionLog = try container.decode(Bool.self, forKey: .includeInNotionLog)
        position = try container.decode(NotePoint.self, forKey: .position)
        size = try container.decodeIfPresent(NoteSize.self, forKey: .size) ?? DesignTokens.defaultNoteSize

        if let decodedTabs = try container.decodeIfPresent([MemoTab].self, forKey: .tabs),
           !decodedTabs.isEmpty {
            tabs = decodedTabs
        } else {
            let legacyTitle = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            let legacyItems = try container.decodeIfPresent([TodoItem].self, forKey: .items) ?? []
            // The pre-tab model kept the note's name in `label`, so a rename carries over
            // instead of being dropped. Every old note also got an automatic "Posteight N" from
            // `addNote`, though, and importing those would dress machine-generated numbering up
            // as something the user chose — so only a label they actually changed survives.
            let legacyLabel = try container.decodeIfPresent(String.self, forKey: .label)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let wasRenamed = legacyLabel.map { label in
                !label.isEmpty
                    && label.range(of: "^Posteight [0-9]+$", options: .regularExpression) == nil
            } ?? false
            tabs = [
                MemoTab(
                    name: wasRenamed ? legacyLabel! : "메모 1",
                    title: legacyTitle,
                    items: legacyItems
                )
            ]
        }

        let decodedSelection = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        if let decodedSelection, tabs.contains(where: { $0.id == decodedSelection }) {
            selectedTabID = decodedSelection
        } else {
            selectedTabID = tabs[0].id
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(stickerSymbol, forKey: .stickerSymbol)
        try container.encode(paperHex, forKey: .paperHex)
        try container.encode(penHex, forKey: .penHex)
        try container.encode(penStyle, forKey: .penStyle)
        try container.encode(includeInNotionLog, forKey: .includeInNotionLog)
        try container.encode(position, forKey: .position)
        try container.encode(size, forKey: .size)
        try container.encode(tabs, forKey: .tabs)
        try container.encode(selectedTabID, forKey: .selectedTabID)
    }
}

struct MemoTab: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var title: String
    var items: [TodoItem]

    init(
        id: UUID = UUID(),
        name: String,
        title: String,
        items: [TodoItem] = []
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.items = items
    }
}

struct TrashedStickyNote: Identifiable, Codable, Equatable {
    var id: UUID { note.id }
    var note: StickyNote
    var deletedAt: Date
}

/// A tab closed on its own, kept apart from its note — the note itself may still be open, or
/// gone by the time this is restored. The paper style travels with it so a restore that has to
/// stand up a new note still looks like it belongs to the one it came from.
struct TrashedMemoTab: Identifiable, Codable, Equatable {
    var id: UUID { tab.id }
    var sourceNoteID: UUID
    var tab: MemoTab
    var paperHex: String
    var penHex: String
    var stickerSymbol: String
    /// Optional so trash written before this field existed still decodes — dropping it would
    /// empty the tab trash on the first launch after an upgrade.
    var includeInNotionLog: Bool?
    var deletedAt: Date
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    /// Free-form notes for the item, kept out of the card so the title stays one glanceable line.
    var detail: String?
    var isDone: Bool
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        detail: String? = nil,
        isDone: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isDone = isDone
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

struct NotePoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct NoteSize: Codable, Equatable {
    var width: Double
    var height: Double
}

enum PenStyle: String, Codable, CaseIterable, Identifiable {
    case pencil
    case ballpoint
    case highlighter

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .pencil:
            L("연필", language: language)
        case .ballpoint:
            L("볼펜", language: language)
        case .highlighter:
            L("형광펜", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .pencil:
            "pencil"
        case .ballpoint:
            "pencil.line"
        case .highlighter:
            "highlighter"
        }
    }

    var strokeHeight: CGFloat {
        switch self {
        case .pencil:
            2
        case .ballpoint:
            2.5
        case .highlighter:
            8
        }
    }

    var opacity: Double {
        switch self {
        case .pencil:
            0.75
        case .ballpoint:
            0.9
        case .highlighter:
            0.36
        }
    }
}

struct ColorOption: Identifiable {
    let id = UUID()
    let name: String
    let hex: String
}

struct StickerOption: Identifiable {
    let id = UUID()
    /// The Korean source string, which is also the lookup key.
    let koreanTitle: String
    let symbol: String

    func title(in language: AppLanguage) -> String { L(koreanTitle, language: language) }
}

enum DesignTokens {
    /// A row spends 102pt on chrome — 26 padding, a 20 checkbox, two 16 buttons, three 8 gaps —
    /// so the title only gets `width - 102`. Measured at 15pt medium, a typical Korean title
    /// needs about 230pt of note and an English one up to 304pt: 244 was picked when the app
    /// only spoke Korean and truncated ordinary English titles at roughly 18 characters.
    static let defaultNoteSize = NoteSize(width: 310, height: 292)
    /// Left at 244 on purpose. Raising it would push every saved note wider through `clamped`,
    /// rewriting a layout the user arranged themselves.
    static let minimumNoteSize = NoteSize(width: 244, height: 220)
    static let maximumNoteSize = NoteSize(width: 430, height: 560)

    static let paperColors: [ColorOption] = [
        ColorOption(name: "Blush", hex: "#EED9D8"),
        ColorOption(name: "Butter", hex: "#F0E4BA"),
        ColorOption(name: "Sage", hex: "#D9E4D5"),
        ColorOption(name: "Mist", hex: "#DCE5E7"),
        ColorOption(name: "Lilac", hex: "#E3DCE9"),
        ColorOption(name: "Ivory", hex: "#F3EFE5")
    ]

    static let penColors: [ColorOption] = [
        ColorOption(name: "Rose", hex: "#B84A62"),
        ColorOption(name: "Ink", hex: "#303036"),
        ColorOption(name: "Blue", hex: "#2E6EDB"),
        ColorOption(name: "Green", hex: "#2C7A5A"),
        ColorOption(name: "Purple", hex: "#7653C8"),
        ColorOption(name: "Red", hex: "#D74646")
    ]

    static let stickers: [StickerOption] = [
        StickerOption(koreanTitle: "업무", symbol: "briefcase"),
        StickerOption(koreanTitle: "학업", symbol: "book"),
        StickerOption(koreanTitle: "회의", symbol: "person.2"),
        StickerOption(koreanTitle: "개발", symbol: "laptopcomputer"),
        StickerOption(koreanTitle: "마감", symbol: "calendar"),
        StickerOption(koreanTitle: "긴급", symbol: "exclamationmark.triangle"),
        StickerOption(koreanTitle: "아이디어", symbol: "lightbulb"),
        StickerOption(koreanTitle: "개인", symbol: "house"),
        StickerOption(koreanTitle: "건강", symbol: "heart"),
        StickerOption(koreanTitle: "장보기", symbol: "cart")
    ]
}
