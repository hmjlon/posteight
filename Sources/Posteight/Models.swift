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
            ? [MemoTab(name: "메모 1", title: "", items: [TodoItem(title: "")])]
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
            tabs = [MemoTab(name: "메모 1", title: legacyTitle, items: legacyItems)]
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

    var title: String {
        switch self {
        case .pencil:
            "연필"
        case .ballpoint:
            "볼펜"
        case .highlighter:
            "형광펜"
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
    let title: String
    let symbol: String
}

enum DesignTokens {
    static let defaultNoteSize = NoteSize(width: 244, height: 292)
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
        StickerOption(title: "업무", symbol: "briefcase"),
        StickerOption(title: "학업", symbol: "book"),
        StickerOption(title: "회의", symbol: "person.2"),
        StickerOption(title: "개발", symbol: "laptopcomputer"),
        StickerOption(title: "마감", symbol: "calendar"),
        StickerOption(title: "긴급", symbol: "exclamationmark.triangle"),
        StickerOption(title: "아이디어", symbol: "lightbulb"),
        StickerOption(title: "개인", symbol: "house"),
        StickerOption(title: "건강", symbol: "heart"),
        StickerOption(title: "장보기", symbol: "cart")
    ]
}
