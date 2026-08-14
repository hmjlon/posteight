import AppKit
import Foundation
import SwiftUI

@MainActor
final class PosteightStore: ObservableObject {
    @Published private(set) var notes: [StickyNote] = [] {
        didSet {
            saveNotes()
        }
    }

    @Published private(set) var trashedNotes: [TrashedStickyNote] = [] {
        didSet {
            saveTrashedNotes()
        }
    }

    private let storageKey = "posteight.notes.v1"
    private let trashStorageKey = "posteight.trash.v1"
    private let legacyStorageKey = "posteat.notes.v1"
    private let legacyTrashStorageKey = "posteat.trash.v1"

    init() {
        load()
    }

    @discardableResult
    func addNote() -> UUID {
        let offset = Double(notes.count % 4) * 34
        let note = StickyNote(
            title: Self.todayTitle(),
            stickerSymbol: "tag",
            paperHex: DesignTokens.paperColors[0].hex,
            penHex: DesignTokens.penColors[0].hex,
            includeInNotionLog: false,
            position: NotePoint(x: 270 + offset, y: 240 + offset),
            items: [
                TodoItem(title: "")
            ]
        )
        notes.append(note)
        return note.id
    }

    func moveNoteToTrash(_ noteID: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let note = notes.remove(at: index)
        trashedNotes.insert(TrashedStickyNote(note: note, deletedAt: Date()), at: 0)
    }

    func restoreNote(_ noteID: UUID) {
        guard let index = trashedNotes.firstIndex(where: { $0.id == noteID }) else { return }
        var restoredNote = trashedNotes.remove(at: index).note
        restoredNote.position.x += 22
        restoredNote.position.y += 22
        notes.append(restoredNote)
    }

    func permanentlyDeleteNote(_ noteID: UUID) {
        trashedNotes.removeAll { $0.id == noteID }
    }

    func emptyTrash() {
        trashedNotes.removeAll()
    }

    func moveNote(_ noteID: UUID, by translation: CGSize) {
        updateNote(noteID) { note in
            note.position.x += translation.width
            note.position.y += translation.height
        }
    }

    func updateNotePosition(_ noteID: UUID, position: NotePoint) {
        updateNote(noteID) { note in
            note.position = position
        }
    }

    func resizeNote(_ noteID: UUID, to size: NoteSize) {
        updateNote(noteID) { note in
            note.size = clamped(size)
        }
    }

    func noteTitle(_ noteID: UUID) -> String? {
        notes.first { $0.id == noteID }?.title
    }

    func updateNoteTitle(_ noteID: UUID, title: String) {
        updateNote(noteID) { note in
            note.title = title
        }
    }

    func updatePaperColor(_ noteID: UUID, hex: String) {
        updateNote(noteID) { note in
            note.paperHex = hex
        }
    }

    func updatePenColor(_ noteID: UUID, hex: String) {
        updateNote(noteID) { note in
            note.penHex = hex
        }
    }

    func updatePenStyle(_ noteID: UUID, style: PenStyle) {
        updateNote(noteID) { note in
            note.penStyle = style
        }
    }

    func updateSticker(_ noteID: UUID, symbol: String) {
        updateNote(noteID) { note in
            note.stickerSymbol = symbol
        }
    }

    func updateNotionLog(_ noteID: UUID, include: Bool) {
        updateNote(noteID) { note in
            note.includeInNotionLog = include
        }
    }

    @discardableResult
    func addItem(to noteID: UUID) -> UUID? {
        let itemID = UUID()
        updateNote(noteID) { note in
            note.items.append(TodoItem(id: itemID, title: ""))
        }
        return itemID
    }

    func updateItemTitle(noteID: UUID, itemID: UUID, title: String) {
        updateItem(noteID: noteID, itemID: itemID) { item in
            item.title = title
        }
    }

    func itemTitle(noteID: UUID, itemID: UUID) -> String? {
        notes
            .first { $0.id == noteID }?
            .items
            .first { $0.id == itemID }?
            .title
    }

    func toggleItem(noteID: UUID, itemID: UUID) {
        updateItem(noteID: noteID, itemID: itemID) { item in
            item.isDone.toggle()
            item.completedAt = item.isDone ? Date() : nil
        }
    }

    func deleteItem(noteID: UUID, itemID: UUID) {
        updateNote(noteID) { note in
            note.items.removeAll { $0.id == itemID }
        }
    }

    func dailyLogMarkdown(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let logNotes = notes.filter(\.includeInNotionLog)
        var lines: [String] = ["# \(formatter.string(from: date)) 업무 기록", ""]

        if logNotes.isEmpty {
            lines.append("Notion 기록에 포함된 포스트잇이 없습니다.")
            return lines.joined(separator: "\n")
        }

        for note in logNotes {
            let doneItems = note.items.filter(\.isDone)
            let pendingItems = note.items.filter { !$0.isDone }

            lines.append("## \(note.title)")
            lines.append("")
            lines.append("### 완료한 일")
            lines.append(contentsOf: doneItems.isEmpty ? ["- 없음"] : doneItems.map { "- \($0.title)" })
            lines.append("")
            lines.append("### 남은 일")
            lines.append(contentsOf: pendingItems.isEmpty ? ["- 없음"] : pendingItems.map { "- \($0.title)" })
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func copyDailyLogToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dailyLogMarkdown(), forType: .string)
    }

    private func updateNote(_ noteID: UUID, mutate: (inout StickyNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        mutate(&notes[index])
    }

    private func updateItem(noteID: UUID, itemID: UUID, mutate: (inout TodoItem) -> Void) {
        updateNote(noteID) { note in
            guard let index = note.items.firstIndex(where: { $0.id == itemID }) else { return }
            mutate(&note.items[index])
        }
    }

    private func load() {
        loadNotes()
        loadTrashedNotes()
    }

    private func loadNotes() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey) ??
                UserDefaults.standard.data(forKey: legacyStorageKey),
            let decoded = try? JSONDecoder().decode([StickyNote].self, from: data)
        else {
            notes = Self.sampleNotes
            return
        }

        notes = compacted(decoded)
    }

    private func loadTrashedNotes() {
        guard
            let data = UserDefaults.standard.data(forKey: trashStorageKey) ??
                UserDefaults.standard.data(forKey: legacyTrashStorageKey),
            let decoded = try? JSONDecoder().decode([TrashedStickyNote].self, from: data)
        else {
            trashedNotes = []
            return
        }

        trashedNotes = decoded
    }

    private func saveNotes() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func saveTrashedNotes() {
        guard let data = try? JSONEncoder().encode(trashedNotes) else { return }
        UserDefaults.standard.set(data, forKey: trashStorageKey)
    }

    private func compacted(_ decodedNotes: [StickyNote]) -> [StickyNote] {
        decodedNotes.map { note in
            var compactNote = note
            compactNote.size = clamped(note.size)
            if compactNote.title == "새 포스트잇" || Self.isLegacyDateTitle(compactNote.title) {
                compactNote.title = Self.todayTitle()
            }
            return compactNote
        }
    }

    private func clamped(_ size: NoteSize) -> NoteSize {
        NoteSize(
            width: min(max(size.width, DesignTokens.minimumNoteSize.width), DesignTokens.maximumNoteSize.width),
            height: min(max(size.height, DesignTokens.minimumNoteSize.height), DesignTokens.maximumNoteSize.height)
        )
    }

    private static let sampleNotes: [StickyNote] = [
        StickyNote(
            title: "오늘 업무",
            stickerSymbol: "building.2",
            paperHex: "#FADDE5",
            penHex: "#B84A62",
            penStyle: .ballpoint,
            includeInNotionLog: true,
            position: NotePoint(x: 260, y: 260),
            items: [
                TodoItem(title: "포스트잇 앱 첫 화면 만들기"),
                TodoItem(title: "필통에 색상과 스티커 담기"),
                TodoItem(title: "펜 줄긋기 애니메이션 확인", isDone: true, completedAt: Date())
            ]
        ),
        StickyNote(
            title: "개인 메모",
            stickerSymbol: "house",
            paperHex: "#DCF8E8",
            penHex: "#2C7A5A",
            penStyle: .highlighter,
            includeInNotionLog: false,
            position: NotePoint(x: 590, y: 300),
            items: [
                TodoItem(title: "점심 메뉴 정하기"),
                TodoItem(title: "퇴근 후 장보기")
            ]
        )
    ]

    private static func todayTitle(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yy.MM.dd(E)"
        return formatter.string(from: date)
    }

    private static func isLegacyDateTitle(_ title: String) -> Bool {
        ["yyyy.MM.dd(E)", "yyyy.MM.dd"].contains { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = format
            return formatter.date(from: title) != nil
        }
    }
}
