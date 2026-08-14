import Foundation
import SwiftUI

struct StickyNote: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var stickerSymbol: String
    var paperHex: String
    var penHex: String
    var penStyle: PenStyle
    var includeInNotionLog: Bool
    var position: NotePoint
    var size: NoteSize
    var items: [TodoItem]

    init(
        id: UUID = UUID(),
        title: String,
        stickerSymbol: String,
        paperHex: String,
        penHex: String,
        penStyle: PenStyle = .ballpoint,
        includeInNotionLog: Bool,
        position: NotePoint,
        size: NoteSize = DesignTokens.defaultNoteSize,
        items: [TodoItem] = []
    ) {
        self.id = id
        self.title = title
        self.stickerSymbol = stickerSymbol
        self.paperHex = paperHex
        self.penHex = penHex
        self.penStyle = penStyle
        self.includeInNotionLog = includeInNotionLog
        self.position = position
        self.size = size
        self.items = items
    }
}

struct TrashedStickyNote: Identifiable, Codable, Equatable {
    var id: UUID { note.id }
    var note: StickyNote
    var deletedAt: Date
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var isDone: Bool
    var createdAt: Date
    var completedAt: Date?

    init(id: UUID = UUID(), title: String, isDone: Bool = false, createdAt: Date = Date(), completedAt: Date? = nil) {
        self.id = id
        self.title = title
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
        ColorOption(name: "Pink", hex: "#FADDE5"),
        ColorOption(name: "Butter", hex: "#FFF1A8"),
        ColorOption(name: "Mint", hex: "#DCF8E8"),
        ColorOption(name: "Sky", hex: "#DDEEFF"),
        ColorOption(name: "Lavender", hex: "#E8DDFB"),
        ColorOption(name: "White", hex: "#FFFDF7")
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
        StickerOption(title: "회사", symbol: "building.2"),
        StickerOption(title: "개발", symbol: "laptopcomputer"),
        StickerOption(title: "회의", symbol: "person.2"),
        StickerOption(title: "디자인", symbol: "paintpalette"),
        StickerOption(title: "긴급", symbol: "exclamationmark.triangle"),
        StickerOption(title: "아이디어", symbol: "lightbulb"),
        StickerOption(title: "개인", symbol: "house"),
        StickerOption(title: "공부", symbol: "graduationcap")
    ]
}
