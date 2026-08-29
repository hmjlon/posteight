import AppKit
import Foundation
import SwiftUI

@MainActor
final class PosteightStore: ObservableObject {
    @Published private(set) var notes: [StickyNote] = [] {
        didSet {
            scheduleSave()
        }
    }

    @Published private(set) var trashedNotes: [TrashedStickyNote] = [] {
        didSet {
            scheduleSave()
        }
    }

    @Published private(set) var trashedTabs: [TrashedMemoTab] = [] {
        didSet {
            scheduleSave()
        }
    }

    private let storageKey = "posteight.notes.v1"
    private let trashStorageKey = "posteight.trash.v1"
    private let legacyStorageKey = "posteat.notes.v1"
    private let legacyTrashStorageKey = "posteat.trash.v1"

    // Notes now live in Application Support. These two domains are read-only fallbacks for
    // data written before that move: `swift run` launches an unbundled binary whose standard
    // domain is not the app bundle's, so both were used at different times.
    private let defaults: UserDefaults = {
        guard Bundle.main.bundleIdentifier == nil else { return .standard }
        return UserDefaults(suiteName: "com.younjiyoung.posteight") ?? .standard
    }()

    static let storeDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Posteight", isDirectory: true)

    private let directory: URL
    private let loadLanguage: AppLanguage
    private let notesURL: URL
    private let trashURL: URL
    private let trashedTabsURL: URL

    private var saveTask: Task<Void, Never>?

    /// `directory` is only overridden by tests, so they never touch the real notes on disk.
    /// `language` is what the first load names things in — sample notes and any tab whose name
    /// has to be filled in. It defaults to the source language so tests do not depend on the
    /// language of the machine running them.
    init(directory: URL = PosteightStore.storeDirectory, language: AppLanguage = .korean) {
        self.directory = directory
        self.loadLanguage = language
        self.notesURL = directory.appendingPathComponent("notes.json")
        self.trashURL = directory.appendingPathComponent("trash.json")
        self.trashedTabsURL = directory.appendingPathComponent("trashed-tabs.json")

        load()

        // A debounced save loses up to `saveDelay` of work if the app quits first.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    /// Menu bar status numbers. Blank items are still being typed, so they count for nothing.
    var totalCount: Int {
        notes.reduce(0) { total, note in
            total + note.allItems.filter {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
        }
    }

    var doneCount: Int {
        notes.reduce(0) { total, note in
            total + note.allItems.filter {
                $0.isDone && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
        }
    }

    var remainingCount: Int {
        totalCount - doneCount
    }

    @discardableResult
    func addNote(language: AppLanguage = .korean) -> UUID {
        let offset = Double(notes.count % 4) * 34
        let note = StickyNote(
            stickerSymbol: "tag",
            paperHex: DesignTokens.paperColors[0].hex,
            penHex: DesignTokens.penColors[0].hex,
            includeInNotionLog: false,
            position: NotePoint(x: 270 + offset, y: 240 + offset),
            tabs: [
                MemoTab(
                    name: Lf("메모 %d", language: language, 1),
                    title: Self.todayTitle(language: language),
                    items: [TodoItem(title: "")]
                )
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
        trashedTabs.removeAll()
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
            note.size = Self.clamped(size)
        }
    }

    @discardableResult
    func addTab(to noteID: UUID, language: AppLanguage = .korean) -> UUID? {
        let tabID = UUID()
        updateNote(noteID) { note in
            let nextNumber = note.tabs.count + 1
            note.tabs.append(
                MemoTab(
                    id: tabID,
                    name: Lf("메모 %d", language: language, nextNumber),
                    title: Self.todayTitle(language: language),
                    items: [TodoItem(title: "")]
                )
            )
            note.selectedTabID = tabID
        }
        return notes.contains { note in note.tabs.contains { $0.id == tabID } } ? tabID : nil
    }

    func selectTab(noteID: UUID, tabID: UUID) {
        updateNote(noteID) { note in
            guard note.tabs.contains(where: { $0.id == tabID }) else { return }
            note.selectedTabID = tabID
        }
    }

    /// Closing a tab is the same weight as closing a note — reversible, not a delete — so it goes
    /// through the same trash rather than disappearing outright. Never takes a note's last tab: a
    /// note without one doesn't exist in this model, and the window already has its own close
    /// control for that case. Returns whether it actually moved, so the view can fall back to
    /// that control when it didn't.
    @discardableResult
    func moveTabToTrash(noteID: UUID, tabID: UUID) -> Bool {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteID }),
              notes[noteIndex].tabs.count > 1,
              let tabIndex = notes[noteIndex].tabs.firstIndex(where: { $0.id == tabID }) else {
            return false
        }

        let note = notes[noteIndex]
        let tab = notes[noteIndex].tabs.remove(at: tabIndex)

        // The tab that slides into the closed one's spot becomes selected, the way a browser
        // lands on a neighbor rather than jumping back to the first tab.
        if notes[noteIndex].selectedTabID == tabID {
            let landingIndex = min(tabIndex, notes[noteIndex].tabs.count - 1)
            notes[noteIndex].selectedTabID = notes[noteIndex].tabs[landingIndex].id
        }

        trashedTabs.insert(
            TrashedMemoTab(
                sourceNoteID: noteID,
                tab: tab,
                paperHex: note.paperHex,
                penHex: note.penHex,
                stickerSymbol: note.stickerSymbol,
                deletedAt: Date()
            ),
            at: 0
        )
        return true
    }

    /// Restores into the note it was closed from when that note still exists, or stands up a
    /// fresh note around it when that note is itself gone — a restore should never just vanish.
    func restoreTab(_ trashedTabID: UUID) {
        guard let index = trashedTabs.firstIndex(where: { $0.id == trashedTabID }) else { return }
        let trashed = trashedTabs.remove(at: index)

        if let noteIndex = notes.firstIndex(where: { $0.id == trashed.sourceNoteID }) {
            notes[noteIndex].tabs.append(trashed.tab)
            notes[noteIndex].selectedTabID = trashed.tab.id
        } else {
            let offset = Double(notes.count % 4) * 34
            notes.append(
                StickyNote(
                    stickerSymbol: trashed.stickerSymbol,
                    paperHex: trashed.paperHex,
                    penHex: trashed.penHex,
                    includeInNotionLog: false,
                    position: NotePoint(x: 270 + offset, y: 240 + offset),
                    tabs: [trashed.tab]
                )
            )
        }
    }

    func permanentlyDeleteTab(_ trashedTabID: UUID) {
        trashedTabs.removeAll { $0.id == trashedTabID }
    }

    func tabName(noteID: UUID, tabID: UUID) -> String? {
        tab(noteID: noteID, tabID: tabID)?.name
    }

    func updateTabName(noteID: UUID, tabID: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateTab(noteID: noteID, tabID: tabID) { tab in
            tab.name = trimmed
        }
    }

    func tabTitle(noteID: UUID, tabID: UUID) -> String? {
        tab(noteID: noteID, tabID: tabID)?.title
    }

    func updateTabTitle(noteID: UUID, tabID: UUID, title: String) {
        updateTab(noteID: noteID, tabID: tabID) { tab in
            tab.title = title
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
    func addItem(to noteID: UUID, tabID: UUID) -> UUID? {
        let itemID = UUID()
        updateTab(noteID: noteID, tabID: tabID) { tab in
            tab.items.append(TodoItem(id: itemID, title: ""))
        }
        return itemTitle(noteID: noteID, tabID: tabID, itemID: itemID) == nil ? nil : itemID
    }

    func updateItemTitle(noteID: UUID, tabID: UUID, itemID: UUID, title: String) {
        updateItem(noteID: noteID, tabID: tabID, itemID: itemID) { item in
            item.title = title

            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                item.isDone = false
                item.completedAt = nil
            }
        }
    }

    func itemTitle(noteID: UUID, tabID: UUID, itemID: UUID) -> String? {
        tab(noteID: noteID, tabID: tabID)?
            .items.first { $0.id == itemID }?.title
    }

    /// A detail that is only whitespace is dropped, so "has notes" never lights up for a blank one.
    func updateItemDetail(noteID: UUID, tabID: UUID, itemID: UUID, detail: String) {
        updateItem(noteID: noteID, tabID: tabID, itemID: itemID) { item in
            item.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : detail
        }
    }

    func itemDetail(noteID: UUID, tabID: UUID, itemID: UUID) -> String? {
        tab(noteID: noteID, tabID: tabID)?
            .items.first { $0.id == itemID }?.detail
    }

    func toggleItem(noteID: UUID, tabID: UUID, itemID: UUID) {
        updateItem(noteID: noteID, tabID: tabID, itemID: itemID) { item in
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                item.isDone = false
                item.completedAt = nil
                return
            }

            item.isDone.toggle()
            item.completedAt = item.isDone ? Date() : nil
        }
    }

    func deleteItem(noteID: UUID, tabID: UUID, itemID: UUID) {
        updateTab(noteID: noteID, tabID: tabID) { tab in
            tab.items.removeAll { $0.id == itemID }
        }
    }

    func dailyLogMarkdown(for date: Date = Date(), language: AppLanguage = .korean) -> String {
        Self.dailyLogMarkdown(notes: notes, date: date, language: language)
    }

    nonisolated static func dailyLogMarkdown(
        notes: [StickyNote],
        date: Date = Date(),
        language: AppLanguage = .korean
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let logNotes = notes.filter(\.includeInNotionLog)
        var lines: [String] = ["# " + Lf("%@ 업무 기록", language: language, formatter.string(from: date)), ""]

        if logNotes.isEmpty {
            lines.append(L("Notion 기록에 포함된 메모가 없습니다.", language: language))
            return lines.joined(separator: "\n")
        }

        for note in logNotes {
            for tab in note.tabs {
                let doneItems = tab.items.filter(\.isDone)
                let pendingItems = tab.items.filter { !$0.isDone }

                lines.append("## \(tab.title)")
                lines.append("")
                let none = "- " + L("없음", language: language)
                lines.append("### \(tab.name) · " + L("완료한 일", language: language))
                lines.append(contentsOf: doneItems.isEmpty ? [none] : doneItems.map { "- \($0.title)" })
                lines.append("")
                lines.append("### \(tab.name) · " + L("남은 일", language: language))
                lines.append(contentsOf: pendingItems.isEmpty ? [none] : pendingItems.map { "- \($0.title)" })
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    func copyDailyLogToClipboard(language: AppLanguage = .korean) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dailyLogMarkdown(language: language), forType: .string)
    }

    private func updateNote(_ noteID: UUID, mutate: (inout StickyNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        mutate(&notes[index])
    }

    private func tab(noteID: UUID, tabID: UUID) -> MemoTab? {
        notes.first { $0.id == noteID }?
            .tabs.first { $0.id == tabID }
    }

    private func updateTab(noteID: UUID, tabID: UUID, mutate: (inout MemoTab) -> Void) {
        updateNote(noteID) { note in
            guard let index = note.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            mutate(&note.tabs[index])
        }
    }

    private func updateItem(
        noteID: UUID,
        tabID: UUID,
        itemID: UUID,
        mutate: (inout TodoItem) -> Void
    ) {
        updateTab(noteID: noteID, tabID: tabID) { tab in
            guard let index = tab.items.firstIndex(where: { $0.id == itemID }) else { return }
            mutate(&tab.items[index])
        }
    }

    private func load() {
        loadNotes()
        loadTrashedNotes()
        loadTrashedTabs()
    }

    /// Application Support first, then the two `UserDefaults` domains notes used to live in
    /// (bundled and unbundled), then the `Posteat` keys from before the rename.
    private func storedData(_ url: URL, key: String, legacy: String) -> Data? {
        (try? Data(contentsOf: url))
            ?? defaults.data(forKey: key) ?? defaults.data(forKey: legacy)
            ?? UserDefaults.standard.data(forKey: key)
            ?? UserDefaults.standard.data(forKey: legacy)
    }

    private func loadNotes() {
        guard
            let data = storedData(notesURL, key: storageKey, legacy: legacyStorageKey),
            let decoded = try? JSONDecoder().decode([StickyNote].self, from: data)
        else {
            notes = Self.sampleNotes(language: loadLanguage)
            return
        }

        notes = Self.compacted(decoded, language: loadLanguage)
    }

    private func loadTrashedNotes() {
        guard
            let data = storedData(trashURL, key: trashStorageKey, legacy: legacyTrashStorageKey),
            let decoded = try? JSONDecoder().decode([TrashedStickyNote].self, from: data)
        else {
            trashedNotes = []
            return
        }

        trashedNotes = decoded.map { trashedNote in
            var migrated = trashedNote
            migrated.note = Self.compacted([trashedNote.note], language: loadLanguage)[0]
            return migrated
        }
    }

    /// No legacy home to fall back to — closing a tab on its own is new, so this file either
    /// holds what a previous launch wrote or doesn't exist yet.
    private func loadTrashedTabs() {
        guard
            let data = try? Data(contentsOf: trashedTabsURL),
            let decoded = try? JSONDecoder().decode([TrashedMemoTab].self, from: data)
        else {
            trashedTabs = []
            return
        }

        trashedTabs = decoded
    }

    private static let saveDelay = Duration.milliseconds(500)

    /// Every keystroke mutates `notes`, so coalesce the writes instead of re-encoding the
    /// whole store per character.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes any pending change immediately. Called on quit so the debounce cannot eat it.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        write(notes, to: notesURL)
        write(trashedNotes, to: trashURL)
        write(trashedTabs, to: trashedTabsURL)
    }

    private func write(_ value: some Encodable, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Posteight: failed to save \(url.lastPathComponent): \(error)")
        }
    }

    nonisolated static func compacted(
        _ decodedNotes: [StickyNote],
        language: AppLanguage = .korean
    ) -> [StickyNote] {
        let notes: [StickyNote] = decodedNotes.map { note in
            var compactNote = note
            compactNote.size = clamped(note.size)

            for tabIndex in compactNote.tabs.indices {
                if compactNote.tabs[tabIndex].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    compactNote.tabs[tabIndex].name = Lf("메모 %d", language: language, tabIndex + 1)
                }

                // Older builds let blank rows be checked off; those completions are phantoms.
                for itemIndex in compactNote.tabs[tabIndex].items.indices
                where compactNote.tabs[tabIndex].items[itemIndex].title
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    compactNote.tabs[tabIndex].items[itemIndex].isDone = false
                    compactNote.tabs[tabIndex].items[itemIndex].completedAt = nil
                }

                let title = compactNote.tabs[tabIndex].title
                // Never localized: this compares against what older builds actually wrote to
                // disk, so the literal has to stay exactly what those builds saved.
                if title == "새 포스트잇" {
                    compactNote.tabs[tabIndex].title = todayTitle(language: language)
                } else if let legacyDate = legacyTitleDate(title) {
                    // Reformat to the short style, keeping the day the memo was actually made.
                    compactNote.tabs[tabIndex].title = todayTitle(date: legacyDate, language: language)
                }
            }

            if !compactNote.tabs.contains(where: { $0.id == compactNote.selectedTabID }) {
                compactNote.selectedTabID = compactNote.tabs[0].id
            }
            return compactNote
        }

        return notes
    }

    nonisolated static func clamped(_ size: NoteSize) -> NoteSize {
        NoteSize(
            width: min(max(size.width, DesignTokens.minimumNoteSize.width), DesignTokens.maximumNoteSize.width),
            height: min(max(size.height, DesignTokens.minimumNoteSize.height), DesignTokens.maximumNoteSize.height)
        )
    }

    private static func sampleNotes(language: AppLanguage) -> [StickyNote] { [
        StickyNote(
            stickerSymbol: "building.2",
            paperHex: "#EED9D8",
            penHex: "#B84A62",
            penStyle: .ballpoint,
            includeInNotionLog: true,
            position: NotePoint(x: 260, y: 260),
            tabs: [
                MemoTab(
                    name: Lf("메모 %d", language: language, 1),
                    title: L("오늘 업무", language: language),
                    items: [
                        TodoItem(title: L("메모 앱 첫 화면 만들기", language: language)),
                        TodoItem(title: L("필통에 색상과 스티커 담기", language: language)),
                        TodoItem(
                            title: L("펜 줄긋기 애니메이션 확인", language: language),
                            isDone: true,
                            completedAt: Date()
                        )
                    ]
                )
            ]
        ),
        StickyNote(
            stickerSymbol: "house",
            paperHex: "#D9E4D5",
            penHex: "#2C7A5A",
            penStyle: .highlighter,
            includeInNotionLog: false,
            position: NotePoint(x: 590, y: 300),
            tabs: [
                MemoTab(
                    name: Lf("메모 %d", language: language, 1),
                    title: L("개인 메모", language: language),
                    items: [
                        TodoItem(title: L("점심 메뉴 정하기", language: language)),
                        TodoItem(title: L("퇴근 후 장보기", language: language))
                    ]
                )
            ]
        )
    ] }

    nonisolated static func todayTitle(date: Date = Date(), language: AppLanguage = .korean) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = "yy.MM.dd(E)"
        return formatter.string(from: date)
    }

    /// The old title style used a four-digit year. `DateFormatter` reads "25.08.11" as year 25
    /// under `yyyy`, so require the four digits first — without that guard every note in the
    /// current short style is mistaken for a legacy one and rewritten on load.
    nonisolated static func legacyTitleDate(_ title: String) -> Date? {
        guard title.prefix(4).allSatisfy(\.isNumber) else { return nil }

        for format in ["yyyy.MM.dd(E)", "yyyy.MM.dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = format
            if let date = formatter.date(from: title) { return date }
        }
        return nil
    }
}
