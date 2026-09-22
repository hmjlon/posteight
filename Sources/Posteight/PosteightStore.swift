import AppKit
import Foundation
import SwiftUI

@MainActor
final class PosteightStore: ObservableObject {
    // Presentation state is shared across note windows and never persisted.
    @Published var presentedDetailItemID: UUID?
    @Published var searchFocusRequest: SearchFocusRequest?

    func finishSearchFocus(_ id: UUID) {
        if searchFocusRequest?.id == id { searchFocusRequest = nil }
    }

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
    /// 위치 기준 이전이 끝났다는 표시. 한 번만 돌아야 한다.
    private static let positionsRebasedKey = "posteight.notePositionsRebased"

    // Notes now live in Application Support. These two domains are read-only fallbacks for
    // data written before that move: `swift run` launches an unbundled binary whose standard
    // domain is not the app bundle's, so both were used at different times.
    private let defaults: UserDefaults

    private static var appDefaults: UserDefaults {
        guard Bundle.main.bundleIdentifier == nil else { return .standard }
        return UserDefaults(suiteName: "com.younjiyoung.posteight") ?? .standard
    }

    static private(set) var migrationIsBlocked = false

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
            do { try prepareMigration(from: legacy, to: directory) }
            catch { migrationIsBlocked = true }
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
    /// A marker survives interrupted copies. Archive partial files and retry from the untouched
    /// source rather than mistaking their existence for a completed migration.
    nonisolated static let migrationMarker = ".migration-in-progress"

    nonisolated static func prepareMigration(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        let marker = destination.appendingPathComponent(migrationMarker)
        if manager.fileExists(atPath: marker.path) {
            // A terminated copy may have left an incomplete file or Fonts directory. Keep those
            // bytes for inspection, then retry from the untouched source instead of adopting them.
            let sourceItems = try manager.contentsOfDirectory(atPath: source.path)
            guard migratedItems.contains(where: sourceItems.contains) else { throw StorageFailure.migration }
            let archive = destination.appendingPathComponent("InterruptedMigration-" + UUID().uuidString)
            try manager.createDirectory(at: archive, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            for item in migratedItems {
                let partial = destination.appendingPathComponent(item)
                if manager.fileExists(atPath: partial.path) {
                    try manager.moveItem(at: partial, to: archive.appendingPathComponent(item))
                }
            }
            narrowPermissions(of: archive)
            try manager.removeItem(at: marker)
        }
        if migratedItems.contains(where: {
            manager.fileExists(atPath: destination.appendingPathComponent($0).path)
        }) { return }
        let contents: [String]
        do { contents = try manager.contentsOfDirectory(atPath: source.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return }
        guard migratedItems.contains(where: contents.contains) else { return }
        guard migrateStore(from: source, to: destination) else { throw StorageFailure.migration }
    }

    @discardableResult
    nonisolated static func migrateStore(from source: URL, to destination: URL) -> Bool {
        let manager = FileManager.default
        let marker = destination.appendingPathComponent(migrationMarker)
        guard !manager.fileExists(atPath: marker.path),
              manager.fileExists(atPath: source.path),
              !migratedItems.contains(where: {
                  manager.fileExists(atPath: destination.appendingPathComponent($0).path)
              }) else { return false }
        var attempted: [URL] = []
        do {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try Data().write(to: marker, options: .atomic)
            for item in migratedItems where manager.fileExists(atPath: source.appendingPathComponent(item).path) {
                let target = destination.appendingPathComponent(item)
                // Include an incomplete directory copy in rollback, too.
                attempted.append(target)
                try manager.copyItem(at: source.appendingPathComponent(item), to: target)
            }
            narrowPermissions(of: destination)
            try manager.removeItem(at: marker)
            return !attempted.isEmpty
        } catch {
            NSLog("Posteight: migration failed: \(error)")
            var rolledBack = true
            for target in attempted where manager.fileExists(atPath: target.path) {
                do { try manager.removeItem(at: target) }
                catch { rolledBack = false }
            }
            if rolledBack { try? manager.removeItem(at: marker) }
            return false
        }
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

    /// 예전 빌드는 메모 위치를 `NSScreen.main.visibleFrame` 기준으로 적었다. 그 기준은 포커스와
    /// Dock 을 따라 움직여서, 저장할 때와 복원할 때 값이 달라지면 메모가 그만큼 밀렸다. 기준이
    /// `NSScreen.noteAnchorFrame` 으로 바뀌었으므로 이미 저장된 값을 한 번 옮긴다.
    ///
    /// 옛 기준을 정확히 되살릴 방법은 없다 — 마지막으로 저장한 순간 어느 화면이 포커스를 쥐고
    /// 있었는지가 어디에도 남지 않는다. 그래서 호출하는 쪽이 지금의 `NSScreen.main.visibleFrame`
    /// 을 그 자리에 놓는다. 화면이 한 대고 Dock 과 메뉴 막대가 그때 그대로면 이 값이 정확히
    /// 맞고, 어긋나더라도 `moveOnScreenIfNeeded()` 가 창을 화면 안에 붙잡는다. 한 번 옮기고 나면
    /// 다시는 흔들리지 않는다.
    ///
    /// **창이 하나라도 만들어지기 전에 불러야 한다.** 창 배치가 이 값을 읽고, 한 번 배치한 창은
    /// 다시 배치하지 않는다.
    func rebaseNotePositions(from legacy: NSRect, to anchor: NSRect) {
        guard !defaults.bool(forKey: Self.positionsRebasedKey) else { return }
        let offset = (dx: Double(legacy.minX - anchor.minX), dy: Double(anchor.maxY - legacy.maxY))
        // 메모를 읽지 못한 채 시작했으면 옮길 메모가 아직 없다. 여기서 표시를 남기면 다시 시도로
        // 불러온 예전 메모는 영영 옮겨지지 않으므로, 불러오기가 성공할 때(`retryLoading`)까지 미룬다.
        guard !isStorageBlocked else { pendingRebase = offset; return }
        applyRebase(offset)
    }

    /// 옛 기준으로 적힌 좌표는 살아 있는 메모에만 있지 않다. 휴지통의 메모는 복원하면 그 좌표로
    /// 서고, 이번 실행의 자동 백업은 첫 저장 때 불러온 그대로 쓰인다. 셋 다 같이 옮기지 않으면
    /// 표시가 선 뒤에 되살린 메모가 기준 차이만큼 밀려서 뜬다.
    private func applyRebase(_ offset: (dx: Double, dy: Double)) {
        pendingRebase = nil
        defaults.set(true, forKey: Self.positionsRebasedKey)
        notes = Self.rebasedPositions(notes, dx: offset.dx, dy: offset.dy)
        trashedNotes = Self.rebasedPositions(trashedNotes, dx: offset.dx, dy: offset.dy)
        if needsSessionBackup, let snapshot = loadedSnapshot {
            loadedSnapshot = StoreBackup(
                createdAt: snapshot.createdAt,
                notes: Self.rebasedPositions(snapshot.notes, dx: offset.dx, dy: offset.dy),
                trashedNotes: Self.rebasedPositions(snapshot.trashedNotes, dx: offset.dx, dy: offset.dy),
                trashedTabs: snapshot.trashedTabs
            )
        }
    }

    nonisolated static func rebasedPositions(
        _ trash: [TrashedStickyNote],
        dx: Double,
        dy: Double
    ) -> [TrashedStickyNote] {
        trash.map { entry in
            var entry = entry
            entry.note = rebasedPositions([entry.note], dx: dx, dy: dy)[0]
            return entry
        }
    }

    /// 기준 두 개의 차이만 받는다. 화면을 읽지 않으므로 테스트가 그대로 부를 수 있다.
    nonisolated static func rebasedPositions(
        _ notes: [StickyNote],
        dx: Double,
        dy: Double
    ) -> [StickyNote] {
        guard dx != 0 || dy != 0 else { return notes }
        return notes.map { note in
            var note = note
            note.position = NotePoint(x: note.position.x + dx, y: note.position.y + dy)
            return note
        }
    }

    private let directory: URL
    private let loadLanguage: AppLanguage
    private let notesURL: URL
    private let trashURL: URL
    private let trashedTabsURL: URL

    private var saveTask: Task<Void, Never>?
    /// 읽지 못한 채 시작한 실행에서 받아 둔 위치 기준 차이. 불러오기가 성공하면 그때 옮긴다.
    private var pendingRebase: (dx: Double, dy: Double)?
    @Published private(set) var storageError: StorageFailure?
    @Published private(set) var isStorageBlocked = false
    @Published private(set) var backupDate: Date?
    private var isLoading = false
    private var needsSessionBackup = false
    private var loadedSnapshot: StoreBackup?
    private let migrationSource: URL?
    private let usesDefaultDirectory: Bool
    private var backupURL: URL { directory.appendingPathComponent("backup.json") }
    private var pendingRestoreURL: URL { directory.appendingPathComponent("pending-restore.json") }


    /// `directory` is only overridden by tests, so they never touch the real notes on disk.
    /// `language` is what the first load names things in — sample notes and any tab whose name
    /// has to be filled in. It defaults to the source language so tests do not depend on the
    /// language of the machine running them.
    /// `defaults` 도 테스트만 넘긴다. 위치 기준 이전 표시가 실제 앱의 도메인에 남지 않게 한다.
    init(directory: URL? = nil, language: AppLanguage = .korean, legacyDirectory: URL? = nil,
         defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? Self.appDefaults
        let resolvedDirectory = directory ?? Self.storeDirectory
        self.usesDefaultDirectory = directory == nil
        self.migrationSource = directory == nil ? Self.legacyStoreDirectory : legacyDirectory
        let directory = resolvedDirectory
        self.directory = directory
        self.loadLanguage = language
        self.notesURL = directory.appendingPathComponent("notes.json")
        self.trashURL = directory.appendingPathComponent("trash.json")
        self.trashedTabsURL = directory.appendingPathComponent("trashed-tabs.json")

        retryLoading()

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

    /// 새 메모를 어디에 놓을지. `origin` 은 띄울 화면의 좌상단이고 주 디스플레이면 (0, 0) 이라
    /// 기존 동작 그대로다. 화면을 읽는 일은 부르는 쪽이 한다 — 스토어는 화면을 모르고, 테스트도
    /// 화면 없이 이 값을 만든다. 메모를 새로 세우는 자리가 둘(새 메모, 탭 복원)이라 식은 하나다.
    private func nextNotePosition(origin: NotePoint) -> NotePoint {
        let offset = Double(notes.count % 4) * 34
        return NotePoint(x: origin.x + 270 + offset, y: origin.y + 240 + offset)
    }

    @discardableResult
    func addNote(language: AppLanguage = .korean, origin: NotePoint = NotePoint(x: 0, y: 0)) -> UUID {
        let position = nextNotePosition(origin: origin)
        let note = StickyNote(
            stickerSymbol: "tag",
            paperHex: DesignTokens.paperColors[0].hex,
            penHex: DesignTokens.penColors[0].hex,
            position: position,
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

    /// Move the existing tab into its own note, preserving item identities and reminders.
    @discardableResult
    func detachTab(noteID: UUID, tabID: UUID, position: NotePoint) -> UUID? {
        guard !isStorageBlocked,
              let index = notes.firstIndex(where: { $0.id == noteID }),
              notes[index].tabs.count > 1,
              let tabIndex = notes[index].tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID) }
        var updated = notes
        var detached = updated[index]
        detached.id = UUID()
        detached.tabs = [updated[index].tabs.remove(at: tabIndex)]
        detached.selectedTabID = tabID
        detached.position = position
        if updated[index].selectedTabID == tabID {
            updated[index].selectedTabID = updated[index].tabs[min(tabIndex, updated[index].tabs.count - 1)].id
        }
        updated.append(detached)
        notes = updated
        flush()
        return detached.id
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
                deletedAt: Date(),
                penStyle: note.penStyle,
                fontID: note.fontID,
                fontSize: note.fontSize
            ),
            at: 0
        )
        return true
    }

    /// Restores into the note it was closed from when that note still exists, or stands up a
    /// fresh note around it when that note is itself gone — a restore should never just vanish.
    /// 원래 메모가 탭 한도까지 찼을 때도 새 메모를 세운다. 한도는 탭 추가와 합치기가 지키는
    /// 것이라, 복원만 끼워 넣으면 메모가 한도를 넘긴 채 남고 되풀이할수록 늘어난다.
    func restoreTab(_ trashedTabID: UUID, origin: NotePoint = NotePoint(x: 0, y: 0)) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore) }
        guard let index = trashedTabs.firstIndex(where: { $0.id == trashedTabID }) else { return }
        let trashed = trashedTabs.remove(at: index)

        if let noteIndex = notes.firstIndex(where: { $0.id == trashed.sourceNoteID }),
           notes[noteIndex].tabs.count < MemoSurfaceMetrics.maximumTabCount {
            var restoredTab = trashed.tab
            if restoredTab.stickerSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                restoredTab.stickerSymbol = trashed.stickerSymbol
            }
            notes[noteIndex].tabs.append(restoredTab)
            notes[noteIndex].selectedTabID = restoredTab.id
        } else {
            var note = StickyNote(
                stickerSymbol: trashed.stickerSymbol,
                paperHex: trashed.paperHex,
                penHex: trashed.penHex,
                penStyle: trashed.penStyle ?? .ballpoint,
                position: nextNotePosition(origin: origin),
                tabs: [trashed.tab]
            )
            note.fontID = trashed.fontID
            note.fontSize = trashed.fontSize
            notes.append(note)
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

    /// Only a completely empty row can be removed by backspace. Preserve the first input
    /// and any hidden content; use the current store order rather than a rendered snapshot.
    func deleteEmptyItemBackward(noteID: UUID, tabID: UUID, itemID: UUID) -> UUID? {
        guard let tab = tab(noteID: noteID, tabID: tabID),
              let index = tab.items.firstIndex(where: { $0.id == itemID }), index > 0 else { return nil }
        let item = tab.items[index]
        guard item.title.isEmpty, (item.detail ?? "").isEmpty, item.reminderAt == nil else { return nil }
        let previousID = tab.items[index - 1].id
        endTextUndoGroup()
        deleteItem(noteID: noteID, tabID: tabID, itemID: itemID)
        return previousID
    }

    /// Resolve both ends against live data and publish once so cross-tab moves are atomic.
    @discardableResult
    func moveItem(_ source: TodoItemDrag, toNote noteID: UUID, tab tabID: UUID,
                  before targetID: UUID? = nil) -> Bool {
        guard let sourceNote = notes.firstIndex(where: { $0.id == source.noteID }),
              let sourceTab = notes[sourceNote].tabs.firstIndex(where: { $0.id == source.tabID }),
              let sourceItem = notes[sourceNote].tabs[sourceTab].items.firstIndex(where: { $0.id == source.itemID }),
              let targetNote = notes.firstIndex(where: { $0.id == noteID }),
              let targetTab = notes[targetNote].tabs.firstIndex(where: { $0.id == tabID }) else { return false }
        if let targetID {
            guard targetID != source.itemID,
                  notes[targetNote].tabs[targetTab].items.contains(where: { $0.id == targetID }) else { return false }
        }
        var moved = notes
        let item = moved[sourceNote].tabs[sourceTab].items.remove(at: sourceItem)
        let insertion = targetID.flatMap { id in
            moved[targetNote].tabs[targetTab].items.firstIndex(where: { $0.id == id })
        } ?? moved[targetNote].tabs[targetTab].items.count
        moved[targetNote].tabs[targetTab].items.insert(item, at: insertion)
        moved[targetNote].tabs[targetTab].items = Self.itemsPinnedFirst(moved[targetNote].tabs[targetTab].items)
        // 순서 비교가 먼저다. 아래에서 정렬 기록을 지우고 나면 자리가 그대로인 드롭까지
        // "바뀌었다" 로 읽혀서, 받아들일 수 없는 드롭이 성공한 것처럼 보인다.
        guard moved != notes else { return false }
        // 손으로 순서를 바꾼 순간 완료별 정렬의 "원래 순서"는 더 이상 의미가 없다. 남겨 두면
        // 목록은 정렬 상태가 아닌데 `isCompletionGroupingActive` 만 참으로 남아, 다음에 정렬
        // 버튼을 누를 때 "다시 정렬"이 아니라 "원래 순서 복원"이 돈다. 출발 탭도 같이 지운다
        // — 항목이 빠져나간 쪽도 손으로 건드린 것은 마찬가지다.
        moved[sourceNote].tabs[sourceTab].completionGroupingOriginalOrder = nil
        moved[targetNote].tabs[targetTab].completionGroupingOriginalOrder = nil
        let before = editingSnapshot
        endTextUndoGroup()
        presentedDetailItemID = nil
        notes = moved
        recordEdit(from: before, noteID: source.noteID, tabID: source.tabID)
        return true
    }

    /// 이 드롭을 받으면 목록이 실제로 바뀌는가.
    ///
    /// 고정 블록은 `itemsPinnedFirst` 로 항상 맨 위에 모인다. 그래서 고정 안 된 항목을 고정
    /// 항목 앞자리에 끌어다 놓으면 `moveItem` 이 넣은 직후 정규화가 원위치로 되돌리고,
    /// `moved != notes` 가드에 걸려 조용히 거절된다. 사용자 입장에서는 파란 삽입선을 보고
    /// 손을 뗐는데 목록이 그대로이고, 실패했다는 신호가 없다. 삽입선을 아예 그리지 않으려면
    /// 드롭을 받기 전에 물어봐야 해서 `moveItem` 과 따로 둔다.
    func canMoveItem(_ source: TodoItemDrag, toNote noteID: UUID, tab tabID: UUID,
                     before targetID: UUID? = nil) -> Bool {
        // 맨 뒤에 붙이는 드롭(탭 헤더와 목록 끝의 빈 줄)은 정규화와 다툴 일이 없다.
        guard let targetID else { return true }
        guard targetID != source.itemID,
              let moving = tab(noteID: source.noteID, tabID: source.tabID)?
                  .items.first(where: { $0.id == source.itemID }),
              let target = tab(noteID: noteID, tabID: tabID)?
                  .items.first(where: { $0.id == targetID }) else { return false }
        return moving.isPinned || !target.isPinned
    }

    func isCompletionGroupingActive(noteID: UUID, tabID: UUID) -> Bool {
        tab(noteID: noteID, tabID: tabID)?.completionGroupingOriginalOrder != nil
    }

    func toggleItemPin(noteID: UUID, tabID: UUID, itemID: UUID) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID, tabID: tabID) }
        endTextUndoGroup()
        updateTab(noteID: noteID, tabID: tabID) { tab in
            guard let index = tab.items.firstIndex(where: { $0.id == itemID }),
                  tab.items[index].hasTitle else { return }
            tab.items[index].isPinned.toggle()
            tab.items = Self.itemsPinnedFirst(tab.items)
        }
    }

    /// The first press groups rows; the next restores their earlier order. Items added in between
    /// are kept after the restored rows instead of being discarded.
    @discardableResult
    func toggleItemsByCompletion(noteID: UUID, tabID: UUID) -> Bool {
        guard let tab = tab(noteID: noteID, tabID: tabID) else { return false }
        let items = tab.items
        let rearranged: [TodoItem]
        let originalOrderAfterToggle: [UUID]?
        if let originalOrder = tab.completionGroupingOriginalOrder {
            let originalIDs = Set(originalOrder)
            let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            rearranged = Self.itemsPinnedFirst(originalOrder.compactMap { itemsByID[$0] }
                + items.filter { !originalIDs.contains($0.id) })
            originalOrderAfterToggle = nil
        } else {
            rearranged = Self.itemsGroupedByCompletion(items)
            guard rearranged != items else { return false }
            originalOrderAfterToggle = items.map(\.id)
        }
        let historyBefore = editingSnapshot
        endTextUndoGroup()
        presentedDetailItemID = nil
        let didUpdate = updateTab(noteID: noteID, tabID: tabID) {
            $0.items = rearranged
            $0.completionGroupingOriginalOrder = originalOrderAfterToggle
        }
        guard didUpdate else { return false }
        recordEdit(from: historyBefore, noteID: noteID, tabID: tabID)
        return true
    }

    nonisolated private static func itemsGroupedByCompletion(_ items: [TodoItem]) -> [TodoItem] {
        let pinned = items.filter(\.isPinned)
        let pending = items.filter { !$0.isPinned && $0.hasTitle && !$0.isDone }
        let completed = items.filter { !$0.isPinned && $0.hasTitle && $0.isDone }
        let empty = items.filter { !$0.isPinned && !$0.hasTitle }
        return pinned + pending + completed + empty
    }

    nonisolated private static func itemsPinnedFirst(_ items: [TodoItem]) -> [TodoItem] {
        items.filter(\.isPinned) + items.filter { !$0.isPinned }
    }

    func deleteItem(noteID: UUID, tabID: UUID, itemID: UUID) {
        let historyBefore = editingSnapshot
        defer { recordEdit(from: historyBefore, noteID: noteID, tabID: tabID) }
        updateTab(noteID: noteID, tabID: tabID) { tab in
            tab.items.removeAll { $0.id == itemID }
        }
    }

    nonisolated static func tabPlainText(_ tab: MemoTab) -> String {
        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : tab.title
        let items = tab.items
            .map(\.title)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "- \($0)" }

        return [title, items.isEmpty ? nil : items.joined(separator: "\n\n")]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    /// Clipboard paths are concealed because the general pasteboard is readable by every
    /// process and syncs through Universal Clipboard, and a clipboard manager (Maccy, Raycast)
    /// files whatever passes through it into a permanent plain-text history.
    /// `pasteboard` is only overridden by tests, so running them never disturbs what the user
    /// has on their clipboard.
    func copyTabToClipboard(
        noteID: UUID,
        tabID: UUID,
        to pasteboard: NSPasteboard = .general
    ) {
        guard let tab = tab(noteID: noteID, tabID: tabID) else { return }
        writeConcealed(Self.tabPlainText(tab), to: pasteboard)
    }

    private func writeConcealed(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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

    func retryLoading() {
        saveTask?.cancel()
        isLoading = true
        defer { isLoading = false }
        do {
            if let migrationSource, migrationSource != directory {
                do { try Self.prepareMigration(from: migrationSource, to: directory) }
                catch { throw StorageFailure.migration }
            }
            if usesDefaultDirectory { Self.migrationIsBlocked = false }
            try finishPendingRestore()
            let loadedNotes: [StickyNote]? = try read(notesURL, key: storageKey, legacy: legacyStorageKey)
            let loadedTrash: [TrashedStickyNote]? = try read(trashURL, key: trashStorageKey, legacy: legacyTrashStorageKey)
            let loadedTabs: [TrashedMemoTab]? = try read(trashedTabsURL)
            let snapshot = StoreBackup(notes: loadedNotes ?? Self.sampleNotes(language: loadLanguage),
                                       trashedNotes: loadedTrash ?? [], trashedTabs: loadedTabs ?? [])
            try snapshot.validate()
            loadedSnapshot = loadedNotes == nil && loadedTrash == nil && loadedTabs == nil ? nil : snapshot
            needsSessionBackup = loadedSnapshot != nil
            clearEditingHistory()
            historyRevision += 1
            presentedDetailItemID = nil
            searchFocusRequest = nil
            isStorageBlocked = false
            apply(snapshot)
            // 창이 서기 전에 옮겨야 한다. 이 호출이 끝난 뒤에야 새로 나타난 메모의 창이 열린다.
            if let pendingRebase { applyRebase(pendingRebase) }
            storageError = nil
            refreshBackupDate()
            purgeExpiredTrash()
            // Persist migrations and trash expiry as before, but only after all files decode.
            isLoading = false
            scheduleSave()
        } catch {
            isStorageBlocked = true
            storageError = (error as? StorageFailure) ?? .read
            refreshBackupDate()
        }
    }

    private func apply(_ snapshot: StoreBackup) {
        notes = Self.compacted(snapshot.notes, language: loadLanguage)
        trashedNotes = snapshot.trashedNotes.map {
            var entry = $0
            entry.note = Self.compacted([entry.note], language: loadLanguage)[0]
            return entry
        }
        trashedTabs = snapshot.trashedTabs
    }

    /// Only a genuinely absent file may fall back to legacy defaults. Read/decoding failures
    /// leave every on-disk file untouched and keep editing disabled until recovery.
    private func read<T: Decodable>(_ url: URL, key: String? = nil, legacy: String? = nil) throws -> T? {
        let data: Data?
        do { data = try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            if let key, let legacy {
                data = defaults.data(forKey: key) ?? defaults.data(forKey: legacy)
                    ?? UserDefaults.standard.data(forKey: key) ?? UserDefaults.standard.data(forKey: legacy)
            } else { data = nil }
        }
        guard let data else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
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

    private static let saveDelay = Duration.milliseconds(500)

    /// Every keystroke mutates `notes`, so coalesce the writes instead of re-encoding the
    /// whole store per character.
    private func scheduleSave() {
        guard !isLoading, !isStorageBlocked else { return }
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
        guard !isStorageBlocked, !isLoading else { return }
        do {
            if needsSessionBackup, let loadedSnapshot {
                try write(loadedSnapshot, to: backupURL)
                needsSessionBackup = false
                refreshBackupDate()
            }
            let encoder = JSONEncoder()
            try writeTogether([(try encoder.encode(notes), notesURL),
                               (try encoder.encode(trashedNotes), trashURL),
                               (try encoder.encode(trashedTabs), trashedTabsURL)])
            storageError = nil
        } catch {
            storageError = .save
            NSLog("Posteight: failed to save: \(error)")
        }
    }

    /// 메모와 휴지통 세 파일을 함께 바꾼다. 셋을 모두 옆에 써 두고, 바꿔 끼울 자리를 확인한 뒤에야
    /// 제자리로 옮긴다. 하나씩 쓰면 휴지통으로 옮기거나 되살린 메모처럼 두 파일 사이를 오가는 항목이,
    /// 두 번째 파일에서 디스크가 차는 순간 어느 파일에도 없게 됐다. 오류를 띄운 채 그대로 종료하면
    /// 그 메모는 사라진다. 옮기기(`rename`)는 데이터를 쓰지 않으므로 디스크가 차서 실패하지 않는다.
    private func writeTogether(_ encoded: [(data: Data, url: URL)]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var staged: [(temporary: URL, destination: URL)] = []
        defer { for file in staged { try? manager.removeItem(at: file.temporary) } }
        for file in encoded {
            let temporary = directory.appendingPathComponent(".\(file.url.lastPathComponent).saving")
            try file.data.write(to: temporary)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            staged.append((temporary, file.url))
        }
        // 파일 자리에 폴더가 있으면 그 파일 하나만 옮기지 못하므로, 옮기기 전에 걸러 낸다.
        for file in staged {
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: file.destination.path, isDirectory: &isDirectory), isDirectory.boolValue {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: file.destination.path])
            }
        }
        for file in staged {
            guard rename(file.temporary.path, file.destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        staged.removeAll()
    }

    func createBackup() throws {
        guard !isStorageBlocked else { throw storageError ?? StorageFailure.read }
        let snapshot = StoreBackup(notes: notes, trashedNotes: trashedNotes, trashedTabs: trashedTabs)
        try write(snapshot, to: backupURL)
        needsSessionBackup = false
        refreshBackupDate()
    }

    /// Validate before touching the live store. Preserve the original bytes, including corrupt
    /// files, before replacing anything. A failed restore leaves backup.json available for retry.
    func restoreBackup() throws {
        guard storageError != .migration else { throw StorageFailure.migration }
        let snapshot = try JSONDecoder().decode(StoreBackup.self, from: Data(contentsOf: backupURL))
        try snapshot.validate()
        // 아직 디스크에 없는 편집 — 디바운스에 걸렸거나 직전 저장이 실패한 것 — 을 먼저 쓴다.
        // 취소만 하면 그 편집은 복원된 데이터에도 BeforeRestore 사본에도 남지 않는다. 설정의 복원
        // 버튼은 편집 중인 필드를 끝내자마자 이 함수를 부르므로 마지막 편집은 늘 이 창 안에 있다.
        // 그 쓰기가 실패하면 메모리에만 있는 편집을 복원이 지워 버리게 되므로 여기서 멈춘다.
        if !isStorageBlocked, saveTask != nil || storageError == .save {
            flush()
            if storageError == .save { throw StorageFailure.save }
        }
        saveTask?.cancel()
        let archive = directory.appendingPathComponent("BeforeRestore-" + UUID().uuidString, isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: archive, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        for name in ["notes.json", "trash.json", "trashed-tabs.json"] {
            let source = directory.appendingPathComponent(name)
            if manager.fileExists(atPath: source.path) {
                try manager.copyItem(at: source, to: archive.appendingPathComponent(name))
            }
        }
        Self.narrowPermissions(of: archive)
        do {
            // This journal is removed only after every collection is restored. On a crash or
            // partial write, the next load finishes the same restore before exposing any data.
            try write(snapshot, to: pendingRestoreURL)
            try finishPendingRestore()
        } catch {
            isStorageBlocked = true
            storageError = .save
            throw error
        }
        isLoading = true
        clearEditingHistory()
        historyRevision += 1
        presentedDetailItemID = nil
        searchFocusRequest = nil
        isStorageBlocked = false
        apply(snapshot)
        purgeExpiredTrash()
        loadedSnapshot = snapshot
        needsSessionBackup = false
        storageError = nil
        isLoading = false
        flush()
    }

    private func finishPendingRestore() throws {
        guard let snapshot: StoreBackup = try read(pendingRestoreURL) else { return }
        try snapshot.validate()
        try write(snapshot.notes, to: notesURL)
        try write(snapshot.trashedNotes, to: trashURL)
        try write(snapshot.trashedTabs, to: trashedTabsURL)
        try FileManager.default.removeItem(at: pendingRestoreURL)
    }

    private func refreshBackupDate() {
        backupDate = (try? JSONDecoder().decode(StoreBackup.self, from: Data(contentsOf: backupURL)))?.createdAt
    }

    private func write(_ value: some Encodable, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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

    /// 정수로 맞춘다. 크기 조절은 마우스 좌표 차이를 그대로 받고 그 값은 Retina 에서 0.5 단위로
    /// 들어온다. 폭이 소수로 남으면 창 원점도 소수가 되고(자리는 중심으로 저장한다), 배율이 1x 인
    /// 외장 모니터에서 글자가 반 픽셀에 걸려 번진다. 불러올 때도 이 식을 지나므로 예전 빌드가
    /// 적어 둔 소수 크기까지 여기서 정리된다.
    ///
    /// `visible` 은 이 메모가 놓일 화면의 `visibleFrame` 이다. 주면 그 안에 들어가게 줄인다.
    /// 화면보다 큰 메모는 **줄일 수 없는** 메모가 되기 때문이다 — 크기 조절 손잡이가 오른쪽 아래
    /// 모서리에 있어서, 아래가 화면 밖으로 나가면 손잡이도 같이 나간다. MacBook Air 13" 를 "더
    /// 크게" 최대로 두면 화면이 1024×640pt 고, 메뉴 막대와 Dock 을 빼면 최대 메모 높이 560 이
    /// 들어가지 않는다.
    ///
    /// 최소 크기가 마지막에 이긴다. 화면이 그보다 작아도 메모를 읽을 수 없게 만들지는 않는다.
    nonisolated static func clamped(_ size: NoteSize, within visible: NSRect? = nil) -> NoteSize {
        func fit(_ value: Double, _ lower: Double, _ upper: Double, _ screen: Double?) -> Double {
            max(lower, min(value, upper, screen ?? .infinity)).rounded()
        }
        return NoteSize(
            width: fit(size.width, DesignTokens.minimumNoteSize.width,
                       DesignTokens.maximumNoteSize.width, visible.map { Double($0.width) }),
            height: fit(size.height, DesignTokens.minimumNoteSize.height,
                        DesignTokens.maximumNoteSize.height, visible.map { Double($0.height) })
        )
    }

    private static func sampleNotes(language: AppLanguage) -> [StickyNote] { [
        StickyNote(
            stickerSymbol: "building.2",
            paperHex: "#EED9D8",
            penHex: "#B84A62",
            penStyle: .ballpoint,
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
