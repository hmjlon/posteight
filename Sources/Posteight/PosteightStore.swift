import AppKit
import Foundation
import SwiftUI

@MainActor
final class PosteightStore: ObservableObject {
    // Presentation state is shared across note windows and never persisted.
    @Published var presentedDetailItemID: UUID?

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

    // Session history belongs to the document, not AppKit's temporary field editor.
    @Published private(set) var historyRevision = 0
    @Published private(set) var historyWindowRequest: HistoryWindowRequest?
    private var undoEntries: [EditingHistoryEntry] = []
    private var redoEntries: [EditingHistoryEntry] = []
    private var coalescingKey: String?

    var canUndo: Bool { !undoEntries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }

    func endTextUndoGroup() { coalescingKey = nil }

    func clearEditingHistory() {
        undoEntries.removeAll()
        redoEntries.removeAll()
        endTextUndoGroup()
    }

    private var editingSnapshot: EditingSnapshot {
        EditingSnapshot(notes: notes, trashedNotes: trashedNotes, trashedTabs: trashedTabs)
    }

    private func recordEdit(from before: EditingSnapshot, key: String? = nil,
                            noteID: UUID? = nil, tabID: UUID? = nil) {
        let after = editingSnapshot
        guard before != after else { return }
        if let key, coalescingKey == key, let last = undoEntries.last,
           case let .data(original, _) = last.change {
            undoEntries[undoEntries.count - 1].change = .data(before: original, after: after)
        } else {
            undoEntries.append(EditingHistoryEntry(change: .data(before: before, after: after),
                                                   key: key, noteID: noteID, tabID: tabID))
        }
        if undoEntries.count > 100 { undoEntries.removeFirst(undoEntries.count - 100) }
        redoEntries.removeAll()
        coalescingKey = key
    }

    func recordClosedWindow(_ noteID: UUID) {
        guard notes.contains(where: { $0.id == noteID }) else { return }
        undoEntries.append(EditingHistoryEntry(change: .closedWindow(noteID), noteID: noteID))
        if undoEntries.count > 100 { undoEntries.removeFirst() }
        redoEntries.removeAll()
        endTextUndoGroup()
    }

    @discardableResult
    func undo() -> Bool {
        guard let entry = undoEntries.popLast() else { return false }
        applyHistory(entry, undo: true)
        redoEntries.append(entry)
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let entry = redoEntries.popLast() else { return false }
        applyHistory(entry, undo: false)
        undoEntries.append(entry)
        return true
    }

    private func applyHistory(_ entry: EditingHistoryEntry, undo: Bool) {
        endTextUndoGroup()
        // Advance before publishing notes so live editors reject pending, stale end-edit writes.
        historyRevision += 1
        switch entry.change {
        case let .closedWindow(noteID):
            historyWindowRequest = HistoryWindowRequest(noteID: noteID, show: undo)
        case let .data(before, after):
            let snapshot = undo ? before : after
            let current = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
            notes = snapshot.notes.map { saved in
                var note = saved
                // Dragging and resizing are not content edits; never rewind a user's layout.
                if let live = current[note.id] {
                    note.position = live.position
                    note.size = live.size
                }
                if note.id == entry.noteID, let tabID = entry.tabID,
                   note.tabs.contains(where: { $0.id == tabID }) { note.selectedTabID = tabID }
                return note
            }
            trashedNotes = snapshot.trashedNotes
            trashedTabs = snapshot.trashedTabs
            if let noteID = entry.noteID, notes.contains(where: { $0.id == noteID }) {
                historyWindowRequest = HistoryWindowRequest(noteID: noteID, show: true)
            }
        }
        flush()
    }

    private func textHistoryKey(_ field: String, old: String, new: String) -> String {
        field + (new.count < old.count ? ":delete" : new.count > old.count ? ":insert" : ":replace")
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

    static let storeDirectory: URL = {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Posteight", isDirectory: true)
        // Both this store and NoteFontLibrary derive their paths from here, and either can be
        // built first. Migrating inside this one-time initialiser is what guarantees neither
        // reaches the container before an older install's files have been copied into it — a
        // font library that got there first would write an empty manifest and the notes
        // migration would then see a populated container and skip.
        if let legacy = legacyStoreDirectory, legacy != directory {
            migrateStore(from: legacy, to: directory)
        }
        return directory
    }()

    /// Where the store lived before the app was sandboxed. Under the sandbox `NSHomeDirectory()`
    /// is the container, so the real home has to come from the password database.
    nonisolated static var legacyStoreDirectory: URL? {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Posteight", isDirectory: true)
    }

    nonisolated static let migratedItems = ["notes.json", "trash.json", "trashed-tabs.json", "Fonts"]

    /// Turning on the sandbox moves Application Support into the container. macOS migrates the
    /// old location automatically only when it is named after the bundle id, and this app's
    /// folder is `Posteight` rather than `com.younjiyoung.posteight`, so nothing is moved for us
    /// and an upgrade would look exactly like every note being thrown away.
    ///
    /// Copies, never moves: leaving the originals in place keeps a way back if this release has
    /// to be rolled back. Runs once — anything already in the container means this has either
    /// run before or the install started life there, and in both cases the container wins.
    @discardableResult
    nonisolated static func migrateStore(from source: URL, to destination: URL) -> Bool {
        let manager = FileManager.default
        func path(_ directory: URL, _ item: String) -> String {
            directory.appendingPathComponent(item).path
        }
        guard manager.fileExists(atPath: source.path),
              !migratedItems.contains(where: { manager.fileExists(atPath: path(destination, $0)) }),
              (try? manager.createDirectory(at: destination, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])) != nil
        else { return false }

        // All or nothing. A partial copy is worse than none: the guard above only asks whether
        // *any* item is already in the container, so one item landing would make every later
        // launch skip the rest, and whatever failed — a locked `trash.json`, a full disk — would
        // stay invisible to the app forever with only an NSLog to say why. Undoing our own
        // copies leaves the container empty so the next launch tries again. The source is never
        // touched, so there is nothing to lose by retrying.
        var copied: [URL] = []
        for item in migratedItems where manager.fileExists(atPath: path(source, item)) {
            let target = destination.appendingPathComponent(item)
            do {
                try manager.copyItem(at: source.appendingPathComponent(item), to: target)
                copied.append(target)
            } catch {
                NSLog("Posteight: failed to migrate \(item), rolling back: \(error)")
                for done in copied { try? manager.removeItem(at: done) }
                return false
            }
        }
        // A copy carries the old 0644 over, and `write(_:to:)` only stamps a mode on creation.
        narrowPermissions(of: destination)
        return !copied.isEmpty
    }

    /// `0700` for directories, `0600` for files, all the way down.
    private nonisolated static func narrowPermissions(of directory: URL) {
        let manager = FileManager.default
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        guard let walker = manager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        else { return }
        for case let url as URL in walker {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            try? manager.setAttributes([.posixPermissions: isDirectory ? 0o700 : 0o600],
                                       ofItemAtPath: url.path)
        }
    }

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
                    name: Lf("메모 %ld", language: language, 1),
                    title: Self.todayTitle(language: language),
                    items: [TodoItem(title: "")]
                )
            ]
        )
        let historyBefore = editingSnapshot
        notes.append(note)
        recordEdit(from: historyBefore, noteID: note.id)
        return note.id
    }

    func moveNoteToTrash(_ noteID: UUID) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID) }
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let note = notes.remove(at: index)
        trashedNotes.insert(TrashedStickyNote(note: note, deletedAt: Date()), at: 0)
    }

    func restoreNote(_ noteID: UUID) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID) }
        guard let index = trashedNotes.firstIndex(where: { $0.id == noteID }) else { return }
        var restoredNote = trashedNotes.remove(at: index).note
        restoredNote.position.x += 22
        restoredNote.position.y += 22
        notes.append(restoredNote)
    }

    func permanentlyDeleteNote(_ noteID: UUID) {
        clearEditingHistory()
        trashedNotes.removeAll { $0.id == noteID }
    }

    func emptyTrash() {
        clearEditingHistory()
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
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID) }
        // The tab strip divides a fixed width and never scrolls, so past this count a tab would
        // be clipped out of reach — selectable by nothing, closable by nothing.
        guard let note = notes.first(where: { $0.id == noteID }),
              note.tabs.count < MemoSurfaceMetrics.maximumTabCount else { return nil }

        let tabID = UUID()
        updateNote(noteID) { note in
            let nextNumber = note.tabs.count + 1
            let inheritedSticker = note.selectedTab?.stickerSymbol ?? "tag"
            note.tabs.append(
                MemoTab(
                    id: tabID,
                    name: Lf("메모 %ld", language: language, nextNumber),
                    title: Self.todayTitle(language: language),
                    stickerSymbol: inheritedSticker,
                    items: [TodoItem(title: "")]
                )
            )
            note.selectedTabID = tabID
        }
        return notes.contains { note in note.tabs.contains { $0.id == tabID } } ? tabID : nil
    }

    func trashSelectedTab(in noteID: UUID) {
        guard let note = notes.first(where: { $0.id == noteID }) else { return }
        if note.tabs.count > 1 {
            moveTabToTrash(noteID: noteID, tabID: note.selectedTabID)
        } else {
            moveNoteToTrash(noteID)
        }
        flush()
    }

    /// Move all tabs without copying their identities or putting a duplicate into the trash.
    @discardableResult
    func mergeNotes(from sourceID: UUID, into targetID: UUID) -> Bool {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: targetID) }
        guard sourceID != targetID,
              let source = notes.first(where: { $0.id == sourceID }),
              let targetIndex = notes.firstIndex(where: { $0.id == targetID }),
              notes[targetIndex].tabs.count + source.tabs.count <= MemoSurfaceMetrics.maximumTabCount else { return false }
        var merged = notes
        merged[targetIndex].tabs.append(contentsOf: source.tabs)
        merged[targetIndex].selectedTabID = source.selectedTabID
        merged.removeAll { $0.id == sourceID }
        notes = merged
        flush()
        return true
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
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID, tabID: tabID) }
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
                stickerSymbol: tab.stickerSymbol,
                includeInNotionLog: note.includeInNotionLog,
                deletedAt: Date()
            ),
            at: 0
        )
        return true
    }

    /// Restores into the note it was closed from when that note still exists, or stands up a
    /// fresh note around it when that note is itself gone — a restore should never just vanish.
    func restoreTab(_ trashedTabID: UUID) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore) }
        guard let index = trashedTabs.firstIndex(where: { $0.id == trashedTabID }) else { return }
        let trashed = trashedTabs.remove(at: index)

        if let noteIndex = notes.firstIndex(where: { $0.id == trashed.sourceNoteID }) {
            var restoredTab = trashed.tab
            if restoredTab.stickerSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                restoredTab.stickerSymbol = trashed.stickerSymbol
            }
            notes[noteIndex].tabs.append(restoredTab)
            notes[noteIndex].selectedTabID = restoredTab.id
        } else {
            let offset = Double(notes.count % 4) * 34
            notes.append(
                StickyNote(
                    stickerSymbol: trashed.stickerSymbol,
                    paperHex: trashed.paperHex,
                    penHex: trashed.penHex,
                    includeInNotionLog: trashed.includeInNotionLog ?? false,
                    position: NotePoint(x: 270 + offset, y: 240 + offset),
                    tabs: [trashed.tab]
                )
            )
        }
    }

    func permanentlyDeleteTab(_ trashedTabID: UUID) {
        clearEditingHistory()
        trashedTabs.removeAll { $0.id == trashedTabID }
    }

    func tabName(noteID: UUID, tabID: UUID) -> String? {
        tab(noteID: noteID, tabID: tabID)?.name
    }

    func updateTabName(noteID: UUID, tabID: UUID, name: String) {
        let historyBefore = editingSnapshot
        let historyKey = textHistoryKey("name:\(tabID)", old: tabName(noteID: noteID, tabID: tabID) ?? "", new: name)
        defer { recordEdit(from: historyBefore, key: historyKey, noteID: noteID, tabID: tabID) }
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
        let historyBefore = editingSnapshot
        let historyKey = textHistoryKey("title:\(tabID)", old: tabTitle(noteID: noteID, tabID: tabID) ?? "", new: title)
        defer { recordEdit(from: historyBefore, key: historyKey, noteID: noteID, tabID: tabID) }
        updateTab(noteID: noteID, tabID: tabID) { tab in
            tab.title = title
        }
    }

    func updatePaperColor(_ noteID: UUID, hex: String) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID) }
        updateNote(noteID) { note in
            note.paperHex = hex
        }
    }

    func updatePenColor(_ noteID: UUID, hex: String) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID) }
        updateNote(noteID) { note in
            note.penHex = hex
        }
    }

    func updateFontSize(_ noteID: UUID, size: NoteFontSize?) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID) }
        updateNote(noteID) { $0.fontSize = size }
    }

    func updateFont(_ noteID: UUID, fontID: String?) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID) }
        updateNote(noteID) { $0.fontID = fontID }
    }

    func updatePenStyle(_ noteID: UUID, style: PenStyle) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID) }
        updateNote(noteID) { note in
            note.penStyle = style
        }
    }

    func updateTabSticker(noteID: UUID, tabID: UUID, symbol: String) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID, tabID: tabID) }
        updateTab(noteID: noteID, tabID: tabID) { tab in
            tab.stickerSymbol = symbol
        }
    }

    func updateNotionLog(_ noteID: UUID, include: Bool) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID) }
        updateNote(noteID) { note in
            note.includeInNotionLog = include
        }
    }

    @discardableResult
    func addItem(to noteID: UUID, tabID: UUID) -> UUID? {
        let itemID = UUID()
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, key: "item:\(itemID):insert", noteID: noteID, tabID: tabID) }
        let didAdd = updateTab(noteID: noteID, tabID: tabID) { tab in
            tab.items.append(TodoItem(id: itemID, title: ""))
        }
        return didAdd ? itemID : nil
    }

    func updateItemTitle(noteID: UUID, tabID: UUID, itemID: UUID, title: String) {
        let historyBefore = editingSnapshot
        let historyKey = textHistoryKey("item:\(itemID)", old: itemTitle(noteID: noteID, tabID: tabID, itemID: itemID) ?? "", new: title)
        defer { recordEdit(from: historyBefore, key: historyKey, noteID: noteID, tabID: tabID) }
        updateItem(noteID: noteID, tabID: tabID, itemID: itemID) { item in
            item.title = title

            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                item.isDone = false
                item.completedAt = nil
            }
        }
    }

    func setReminder(noteID: UUID, tabID: UUID, itemID: UUID, date: Date?) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID, tabID: tabID) }
        updateItem(noteID: noteID, tabID: tabID, itemID: itemID) { item in
            item.reminderAt = date
        }
        flush()
    }

    func itemTitle(noteID: UUID, tabID: UUID, itemID: UUID) -> String? {
        tab(noteID: noteID, tabID: tabID)?
            .items.first { $0.id == itemID }?.title
    }

    /// A detail that is only whitespace is dropped, so "has notes" never lights up for a blank one.
    func updateItemDetail(noteID: UUID, tabID: UUID, itemID: UUID, detail: String) {
        let historyBefore = editingSnapshot
        let historyKey = textHistoryKey("detail:\(itemID)", old: itemDetail(noteID: noteID, tabID: tabID, itemID: itemID) ?? "", new: detail)
        defer { recordEdit(from: historyBefore, key: historyKey, noteID: noteID, tabID: tabID) }
        updateItem(noteID: noteID, tabID: tabID, itemID: itemID) { item in
            item.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : detail
        }
    }

    func itemDetail(noteID: UUID, tabID: UUID, itemID: UUID) -> String? {
        tab(noteID: noteID, tabID: tabID)?
            .items.first { $0.id == itemID }?.detail
    }

    func toggleItem(noteID: UUID, tabID: UUID, itemID: UUID) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID, tabID: tabID) }
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
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID, tabID: tabID) }
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

        let none = "- " + L("없음", language: language)

        for note in logNotes {
            for tab in note.tabs {
                let doneItems = tab.items.filter(\.isDone)
                let pendingItems = tab.items.filter { !$0.isDone }

                lines.append("## \(tab.name) · \(tab.title)")
                lines.append("")
                lines.append("### " + L("완료한 일", language: language))
                lines.append(contentsOf: doneItems.isEmpty ? [none] : doneItems.map { "- \($0.title)" })
                lines.append("")
                lines.append("### " + L("남은 일", language: language))
                lines.append(contentsOf: pendingItems.isEmpty ? [none] : pendingItems.map { "- \($0.title)" })
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// The one path memo text takes out of the app. The general pasteboard is readable by every
    /// process and syncs through Universal Clipboard, and a clipboard manager (Maccy, Raycast)
    /// files whatever passes through it into a permanent plain-text history.
    /// `pasteboard` is only overridden by tests, so running them never disturbs what the user
    /// has on their clipboard.
    func copyDailyLogToClipboard(language: AppLanguage = .korean, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(dailyLogMarkdown(language: language), forType: .string)
        // The community convention clipboard managers honour to keep an entry out of their
        // history. It is an extra type on the same item, so pasting is unaffected.
        pasteboard.setString("", forType: Self.concealedPasteboardType)
    }

    nonisolated static let concealedPasteboardType =
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private func updateNote(_ noteID: UUID, mutate: (inout StickyNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        mutate(&notes[index])
    }

    private func tab(noteID: UUID, tabID: UUID) -> MemoTab? {
        notes.first { $0.id == noteID }?
            .tabs.first { $0.id == tabID }
    }

    /// Returns whether the tab was found, so callers do not have to read the store back to
    /// find out whether their own write landed.
    @discardableResult
    private func updateTab(noteID: UUID, tabID: UUID, mutate: (inout MemoTab) -> Void) -> Bool {
        var didUpdate = false
        updateNote(noteID) { note in
            guard let index = note.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            didUpdate = true
            mutate(&note.tabs[index])
        }
        return didUpdate
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
        purgeExpiredTrash()
    }

    /// The trash is a way back from a mistake, not an archive. Without this, everything a user
    /// ever deleted stays readable in `trash.json` until they happen to press 비우기 — they
    /// believe it is gone and the words are still on disk. The window is announced in the trash
    /// window so nothing disappears unannounced.
    nonisolated static let trashRetentionDays = 30
    private nonisolated static let trashRetention = TimeInterval(trashRetentionDays) * 24 * 60 * 60

    /// Not private: the boundary is what the tests check, and going through a real 30-day-old
    /// file to reach it would only test `Date` arithmetic twice.
    func purgeExpiredTrash(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.trashRetention)
        trashedNotes.removeAll { $0.deletedAt < cutoff }
        trashedTabs.removeAll { $0.deletedAt < cutoff }
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

    /// Notes live as plain JSON at a fixed path, so the file mode is the only thing standing
    /// between them and every other process running as this user. Default creation is `0755`
    /// for the directory and `0644` for the files; both are narrowed here.
    private func write(_ value: some Encodable, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            // `createDirectory` ignores its attributes for a directory that already exists, so
            // installs that predate this narrow the mode on their next save instead.
            try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

            if !manager.fileExists(atPath: url.path) {
                manager.createFile(atPath: url.path, contents: nil,
                                   attributes: [.posixPermissions: 0o600])
            }
            try data.write(to: url, options: .atomic)
            // Stamped on every save, not just creation. An atomic replacement carries the old
            // file's mode across, which is what keeps 0600 once it is set — but it is also what
            // left a file written by a build older than this one at 0644 for good.
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
                if compactNote.tabs[tabIndex].stickerSymbol
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    compactNote.tabs[tabIndex].stickerSymbol = "tag"
                }

                if compactNote.tabs[tabIndex].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    compactNote.tabs[tabIndex].name = Lf("메모 %ld", language: language, tabIndex + 1)
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

            if let firstTab = compactNote.tabs.first,
               !compactNote.tabs.contains(where: { $0.id == compactNote.selectedTabID }) {
                compactNote.selectedTabID = firstTab.id
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
                    name: Lf("메모 %ld", language: language, 1),
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
                    name: Lf("메모 %ld", language: language, 1),
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
