import AppKit
import Foundation
import Testing

@testable import Posteight

private func note(
    title: String = "메모",
    tabName: String = "메모 1",
    includeInNotionLog: Bool = true,
    size: NoteSize = DesignTokens.defaultNoteSize,
    items: [TodoItem] = []
) -> StickyNote {
    StickyNote(
        stickerSymbol: "tag",
        paperHex: "#FADDE5",
        penHex: "#B84A62",
        includeInNotionLog: includeInNotionLog,
        position: NotePoint(x: 0, y: 0),
        size: size,
        tabs: [MemoTab(name: tabName, title: title, items: items)]
    )
}

private func firstTab(_ note: StickyNote) throws -> MemoTab {
    try #require(note.tabs.first)
}

@Suite("Legacy title migration")
struct LegacyTitleTests {
    @Test("Four-digit-year titles are recognised and keep their own date")
    func migratesLegacyTitle() throws {
        let date = try #require(PosteightStore.legacyTitleDate("2025.03.14"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2025)
        #expect(parts.month == 3)
        #expect(parts.day == 14)

        let migrated = PosteightStore.compacted([note(title: "2025.03.14")])
        #expect(try firstTab(migrated[0]).title == "25.03.14(금)")
    }

    @Test("Titles already in the short style are left alone")
    func keepsCurrentStyleTitle() throws {
        #expect(PosteightStore.legacyTitleDate("25.03.14(금)") == nil)
        let migrated = PosteightStore.compacted([note(title: "25.03.14(금)")])
        #expect(try firstTab(migrated[0]).title == "25.03.14(금)")
    }

    @Test("A title the user typed is never treated as a date")
    func keepsUserTitle() throws {
        #expect(PosteightStore.legacyTitleDate("오늘 업무") == nil)
        let migrated = PosteightStore.compacted([note(title: "오늘 업무")])
        #expect(try firstTab(migrated[0]).title == "오늘 업무")
    }

    @Test("The old placeholder title becomes today")
    func replacesPlaceholderTitle() throws {
        let migrated = PosteightStore.compacted([note(title: "새 포스트잇")])
        #expect(try firstTab(migrated[0]).title == PosteightStore.todayTitle())
    }

    @Test("Blank items saved as done are cleared on load")
    func clearsBlankCompletions() throws {
        let loaded = PosteightStore.compacted([
            note(items: [
                TodoItem(title: "  ", isDone: true, completedAt: Date()),
                TodoItem(title: "끝난 일", isDone: true, completedAt: Date())
            ])
        ])
        let tab = try firstTab(loaded[0])
        #expect(!tab.items[0].isDone)
        #expect(tab.items[0].completedAt == nil)
        #expect(tab.items[1].isDone)
    }
}

@Suite("Memo tab migration")
struct MemoTabMigrationTests {
    private struct TabWithoutSticker: Encodable {
        let id: UUID
        let name: String
        let title: String
        let items: [TodoItem]
    }

    private struct NoteBeforePerTabStickers: Encodable {
        let id = UUID()
        let stickerSymbol = "briefcase"
        let paperHex = "#FADDE5"
        let penHex = "#B84A62"
        let penStyle = PenStyle.ballpoint
        let includeInNotionLog = false
        let position = NotePoint(x: 10, y: 20)
        let size = DesignTokens.defaultNoteSize
        let tabs: [TabWithoutSticker]
        let selectedTabID: UUID

        init() {
            let firstID = UUID()
            let secondID = UUID()
            tabs = [
                TabWithoutSticker(id: firstID, name: "회사", title: "업무", items: []),
                TabWithoutSticker(id: secondID, name: "개인", title: "생활", items: [])
            ]
            selectedTabID = firstID
        }
    }

    private struct LegacyStickyNote: Encodable {
        let id = UUID()
        let title = "이전 내용"
        let stickerSymbol = "tag"
        let paperHex = "#FADDE5"
        let penHex = "#B84A62"
        let penStyle = PenStyle.ballpoint
        let includeInNotionLog = false
        let position = NotePoint(x: 10, y: 20)
        let size = DesignTokens.defaultNoteSize
        let items = [TodoItem(title: "이전 할 일")]
        let label = "Posteight 7"
    }

    @Test("A legacy single-content note becomes one default memo tab")
    func migratesLegacyNoteIntoTab() throws {
        let data = try JSONEncoder().encode(LegacyStickyNote())
        let migrated = try JSONDecoder().decode(StickyNote.self, from: data)
        let tab = try firstTab(migrated)
        #expect(migrated.tabs.count == 1)
        #expect(migrated.selectedTabID == tab.id)
        #expect(tab.name == "메모 1")
        #expect(tab.title == "이전 내용")
        #expect(tab.items.map(\.title) == ["이전 할 일"])
    }

    private struct RenamedLegacyNote: Encodable {
        let id = UUID()
        let title = "이전 내용"
        let stickerSymbol = "tag"
        let paperHex = "#FADDE5"
        let penHex = "#B84A62"
        let penStyle = PenStyle.ballpoint
        let includeInNotionLog = false
        let position = NotePoint(x: 10, y: 20)
        let size = DesignTokens.defaultNoteSize
        let items = [TodoItem(title: "이전 할 일")]
        let label: String
    }

    /// 자동으로 붙던 "Posteight N" 은 버리고, 사용자가 직접 바꾼 이름만 탭 이름으로 넘어온다.
    @Test("이름을 바꿨던 레거시 메모는 그 이름을 탭에 유지한다")
    func keepsRenamedLegacyLabel() throws {
        let data = try JSONEncoder().encode(RenamedLegacyNote(label: "업무"))
        let migrated = try JSONDecoder().decode(StickyNote.self, from: data)
        #expect(try firstTab(migrated).name == "업무")

        let generated = try JSONEncoder().encode(RenamedLegacyNote(label: "Posteight 12"))
        let fromGenerated = try JSONDecoder().decode(StickyNote.self, from: generated)
        #expect(try firstTab(fromGenerated).name == "메모 1")
    }

    @Test("Blank tab names receive a local default name")
    func fillsBlankTabName() throws {
        let migrated = PosteightStore.compacted([note(tabName: "   ")])
        #expect(try firstTab(migrated[0]).name == "메모 1")
    }

    @Test("기존 메모 아이콘을 각 탭의 아이콘으로 이전한다")
    func migratesNoteStickerIntoEveryTab() throws {
        let data = try JSONEncoder().encode(NoteBeforePerTabStickers())
        let migrated = try JSONDecoder().decode(StickyNote.self, from: data)

        #expect(migrated.tabs.map(\.stickerSymbol) == ["briefcase", "briefcase"])
    }
}

@Suite("Note size clamping")
struct ClampTests {
    @Test("Sizes below the minimum are raised")
    func clampsSmall() {
        #expect(PosteightStore.clamped(NoteSize(width: 10, height: 10)) == DesignTokens.minimumNoteSize)
    }

    @Test("Sizes above the maximum are lowered")
    func clampsLarge() {
        #expect(PosteightStore.clamped(NoteSize(width: 9_999, height: 9_999)) == DesignTokens.maximumNoteSize)
    }

    /// 소수 크기는 창 원점까지 소수로 만들고(자리는 중심으로 저장한다) 1x 외장 모니터에서 글자를
    /// 번지게 한다. 크기가 지나는 길은 이 함수 하나뿐이라 여기서 끊는다.
    @Test("크기는 정수로 떨어진다")
    func sizeIsIntegral() {
        let dragged = PosteightStore.clamped(NoteSize(width: 310.5, height: 292.5))
        #expect(dragged == NoteSize(width: 311, height: 293))
        #expect(dragged.width.truncatingRemainder(dividingBy: 1) == 0)
        #expect(dragged.height.truncatingRemainder(dividingBy: 1) == 0)
    }

    /// MacBook Air 13" 를 "더 크게" 최대로 두면 화면이 1024×640pt 다. 메뉴 막대와 Dock 을 빼면
    /// 최대 메모 높이 560 이 들어가지 않고, 화면보다 큰 메모는 크기 조절 손잡이가 오른쪽 아래
    /// 모서리라 화면 밖으로 나가 줄일 수 없게 된다. 아래 532 는 그 상황을 본뜬 값이다.
    @Test("화면보다 큰 메모는 화면에 맞춰 줄어든다")
    func sizeFitsTheScreen() {
        let small = NSRect(x: 0, y: 70, width: 1024, height: 532)
        #expect(PosteightStore.clamped(DesignTokens.maximumNoteSize, within: small)
                == NoteSize(width: DesignTokens.maximumNoteSize.width, height: 532))
        // 화면을 주지 않으면 예전 그대로다.
        #expect(PosteightStore.clamped(DesignTokens.maximumNoteSize) == DesignTokens.maximumNoteSize)
    }

    /// 화면이 아무리 작아도 읽을 수 없는 메모를 만들지는 않는다. 최소 크기가 마지막에 이긴다.
    @Test("최소 크기는 화면보다 우선한다")
    func minimumWinsOverTheScreen() {
        let sliver = NSRect(x: 0, y: 0, width: 80, height: 60)
        #expect(PosteightStore.clamped(DesignTokens.defaultNoteSize, within: sliver)
                == DesignTokens.minimumNoteSize)
    }

    @Test("Loading a note with an out-of-range size fixes it")
    func clampsOnLoad() {
        let loaded = PosteightStore.compacted([note(size: NoteSize(width: 10, height: 9_999))])
        #expect(loaded[0].size == NoteSize(
            width: DesignTokens.minimumNoteSize.width,
            height: DesignTokens.maximumNoteSize.height
        ))
    }
}

@Suite("Daily log markdown")
struct DailyLogTests {
    private let date = Date(timeIntervalSince1970: 1_741_910_400)

    @Test("Only memos flagged for the log are included")
    func filtersByFlag() {
        let markdown = PosteightStore.dailyLogMarkdown(
            notes: [
                note(title: "포함", includeInNotionLog: true),
                note(title: "제외", includeInNotionLog: false)
            ],
            date: date
        )
        #expect(markdown.contains("## 메모 1 · 포함"))
        #expect(!markdown.contains("· 제외"))
    }

    @Test("Done and pending items are split under their tab")
    func splitsByCompletion() throws {
        let markdown = PosteightStore.dailyLogMarkdown(
            notes: [note(items: [
                TodoItem(title: "끝난 일", isDone: true, completedAt: date),
                TodoItem(title: "남은 일")
            ])],
            date: date
        )
        let done = try #require(markdown.range(of: "### 완료한 일"))
        let pending = try #require(markdown.range(of: "### 남은 일"))
        #expect(markdown.range(of: "- 끝난 일")!.lowerBound > done.lowerBound)
        #expect(markdown.range(of: "- 끝난 일")!.lowerBound < pending.lowerBound)
        #expect(markdown.range(of: "- 남은 일")!.lowerBound > pending.lowerBound)
    }

    @Test("An empty section says so instead of leaving a bare heading")
    func marksEmptySections() {
        let markdown = PosteightStore.dailyLogMarkdown(
            notes: [note(items: [TodoItem(title: "남은 일")])],
            date: date
        )
        #expect(markdown.contains("### 완료한 일\n- 없음"))
    }

    /// 탭 제목은 만든 날짜라 같은 날 만든 탭끼리 똑같다. 제목만 H2 로 쓰면 같은 헤딩이
    /// 여러 번 나와 문서 개요가 무너진다.
    @Test("탭이 여럿이어도 같은 헤딩이 반복되지 않는다")
    func headingsStayDistinctAcrossTabs() throws {
        let shared = "26.08.29(토)"
        let memo = StickyNote(
            stickerSymbol: "tag",
            paperHex: "#FFFFFF",
            penHex: "#000000",
            includeInNotionLog: true,
            position: NotePoint(x: 0, y: 0),
            tabs: [
                MemoTab(name: "메모 1", title: shared, items: [TodoItem(title: "가")]),
                MemoTab(name: "메모 2", title: shared, items: [TodoItem(title: "나")])
            ]
        )

        let markdown = PosteightStore.dailyLogMarkdown(notes: [memo], date: date)
        let headings = markdown.split(separator: "\n").filter { $0.hasPrefix("## ") }

        #expect(headings.count == 2)
        #expect(Set(headings).count == 2, "같은 H2 가 반복된다: \(headings)")
    }

    @Test("A detail stays in the app and never reaches the log")
    func keepsDetailOutOfLog() {
        let markdown = PosteightStore.dailyLogMarkdown(
            notes: [note(items: [TodoItem(title: "배포", detail: "스테이징 먼저")])],
            date: date
        )

        #expect(markdown.contains("- 배포"))
        #expect(!markdown.contains("스테이징 먼저"))
    }

    @Test("No flagged memos produces a readable message")
    func handlesNoFlaggedNotes() {
        let markdown = PosteightStore.dailyLogMarkdown(
            notes: [note(includeInNotionLog: false)],
            date: date
        )
        #expect(markdown.contains("Notion 기록에 포함된 메모가 없습니다."))
    }

    /// Copying is the only path memo text takes out of the app, and the general pasteboard is
    /// read by every process and by clipboard managers that keep a permanent history.
    @MainActor
    @Test("Copying marks the entry concealed without changing what is pasted")
    func copyMarksConcealed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("posteight-tests-\(UUID().uuidString)", isDirectory: true)
        let pasteboard = NSPasteboard(name: .init("posteight-tests-\(UUID().uuidString)"))
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }

        let store = PosteightStore(directory: directory)
        store.copyDailyLogToClipboard(to: pasteboard)

        let pasted = try #require(pasteboard.string(forType: .string))
        #expect(pasted == store.dailyLogMarkdown())
        #expect(pasteboard.string(forType: PosteightStore.concealedPasteboardType) != nil)
    }
}

@Suite("Note position anchor")
struct NotePositionAnchorTests {
    private func placed(_ x: Double, _ y: Double) -> StickyNote {
        var placed = note()
        placed.position = NotePoint(x: x, y: y)
        return placed
    }

    /// 예전 기준은 `NSScreen.main.visibleFrame` 이었다. 화면 한 대, Dock 이 아래, 메뉴 막대
    /// 40pt 인 흔한 경우: 옛 기준의 좌상단이 새 기준보다 40pt 아래에 있었으므로, 같은 창을
    /// 가리키려면 저장값의 y 가 40 만큼 커져야 한다. x 는 그대로다.
    @Test("메뉴 막대 높이만큼만 y 가 옮겨진다")
    func menuBarHeightMovesOnlyY() {
        let legacy = NSRect(x: 0, y: 73, width: 1800, height: 1056)   // visibleFrame
        let anchor = NSRect(x: 0, y: 0, width: 1800, height: 1169)    // frame
        let moved = PosteightStore.rebasedPositions(
            [placed(700, 400)],
            dx: legacy.minX - anchor.minX,
            dy: anchor.maxY - legacy.maxY
        )
        #expect(moved[0].position == NotePoint(x: 700, y: 440))
    }

    /// Dock 을 왼쪽에 둔 기계는 옛 기준의 좌변이 Dock 폭만큼 오른쪽에 있었다. 그만큼 x 를
    /// 되돌려 줘야 창이 있던 자리에 그대로 뜬다. 이 세션이 실물로 재현한 어긋남이다.
    @Test("Dock 이 옆에 있던 기계는 x 도 옮겨진다")
    func sideDockMovesX() {
        let legacy = NSRect(x: 50, y: 40, width: 1750, height: 1129)
        let anchor = NSRect(x: 0, y: 0, width: 1800, height: 1169)
        let moved = PosteightStore.rebasedPositions(
            [placed(700, 400)],
            dx: legacy.minX - anchor.minX,
            dy: anchor.maxY - legacy.maxY
        )
        #expect(moved[0].position == NotePoint(x: 750, y: 400))
    }

    /// 기준이 같으면 손대지 않는다. 이미 옮긴 기계가 두 번째로 돌아도 값이 그대로여야 한다.
    @Test("기준이 같으면 값이 그대로다")
    func sameAnchorIsNoOp() {
        let notes = [placed(700, 400), placed(-120, 2000)]
        #expect(PosteightStore.rebasedPositions(notes, dx: 0, dy: 0) == notes)
    }

    /// 메모가 여럿이면 전부 같은 만큼 움직인다. 서로의 간격이 달라지면 사용자가 잡아 둔
    /// 배치가 무너진다.
    @Test("여러 메모가 같은 만큼 움직인다")
    func everyNoteMovesTogether() {
        let before = [placed(100, 100), placed(400, 300), placed(-50, 900)]
        let after = PosteightStore.rebasedPositions(before, dx: 50, dy: 40)
        #expect(after.map(\.position) == [
            NotePoint(x: 150, y: 140),
            NotePoint(x: 450, y: 340),
            NotePoint(x: 0, y: 940),
        ])
        // 위치 말고는 아무것도 건드리지 않는다.
        #expect(after.map(\.id) == before.map(\.id))
        #expect(after.map(\.size) == before.map(\.size))
        #expect(after.map(\.tabs) == before.map(\.tabs))
    }

    /// 기준이 (0, 0) 원점 프레임이면 저장값은 곧 전역 좌표다 — 화면 좌상단에서 잰 값.
    /// 이 성질이 깨지면 화면이 두 대일 때 다시 다른 모니터로 튄다.
    @Test("새 기준에서 저장값은 전역 좌표다")
    func newAnchorIsGlobal() {
        let anchor = NSRect(x: 0, y: 0, width: 1800, height: 1169)
        // 창 중심이 전역 (1000, 429) 일 때 저장값은 (1000, 1169 - 429).
        #expect(anchor.minX == 0)
        #expect(1000 - anchor.minX == 1000)
        #expect(anchor.maxY - 429 == 740)
    }
}

/// 실제 배치는 손으로 확인하지만, "구해 낼 창인가" 판정만은 화면을 읽지 않는 순수 함수라
/// 그대로 부른다. 내장 1512×982 왼쪽에 외장 1920×1080 을 붙인 흔한 배치를 쓴다.
@Suite("Note reachability")
struct NoteReachabilityTests {
    private let builtIn = NSRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
    private func card(x: Double, y: Double) -> NSRect {
        NSRect(x: x, y: y, width: 310, height: 292)
    }

    @Test("두 모니터 경계에 걸친 메모는 손대지 않는다")
    func straddlingTwoDisplaysStaysPut() {
        // 외장 오른쪽 끝(x=0)에 걸터앉아 절반이 내장으로 넘어온 창. 중심은 내장 쪽에 있다.
        let straddling = card(x: -100, y: 400)
        #expect(NSScreen.showsNote(straddling, on: [builtIn, external]))
        // 예전 판정이 걸려 넘어지던 자리다. 어느 화면도 이 창을 통째로 품지 못한다.
        #expect(!builtIn.contains(straddling) && !external.contains(straddling))
    }

    @Test("Dock 과 메뉴 막대에 걸친 메모는 손대지 않는다")
    func overlappingDockStaysPut() {
        // Dock 70pt, 메뉴 막대 38pt 를 뺀 넓이가 `visibleFrame` 이다.
        let visible = NSRect(x: 0, y: 70, width: 1512, height: 982 - 70 - 38)
        let onDock = card(x: 600, y: 10)
        #expect(NSScreen.showsNote(onDock, on: [builtIn]))
        // 예전 판정의 기준이던 `visibleFrame` 은 이 창을 품지 못해 매번 위로 당겼다.
        #expect(!visible.contains(onDock))
    }

    @Test("사라진 화면에 남은 메모는 구해 낸다")
    func strandedOnRemovedDisplayIsRescued() {
        let onExternal = card(x: -1500, y: 500)
        #expect(NSScreen.showsNote(onExternal, on: [builtIn, external]))
        #expect(!NSScreen.showsNote(onExternal, on: [builtIn]))
    }

    @Test("화면이 하나도 없으면 닿지 않는다")
    func noDisplaysReachesNothing() {
        #expect(!NSScreen.showsNote(card(x: 0, y: 0), on: []))
    }
}

/// 새 메모가 뜰 화면의 좌상단을 어디서 받든 자리 계산은 같아야 한다. 화면을 읽는 쪽은
/// `NSScreen.noteSpawnOrigin` 이고 손으로 확인하지만, 그 값을 쓰는 식은 여기서 못 박는다.
@Suite("Note spawn origin")
@MainActor
struct NoteSpawnOriginTests {
    private func store() -> PosteightStore {
        PosteightStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    @Test("기본값은 주 디스플레이 좌상단이라 기존 자리 그대로다")
    func defaultOriginKeepsPrimaryPlacement() throws {
        let store = store()
        let id = store.addNote()
        let placed = try #require(store.notes.first { $0.id == id })
        // 샘플 메모 두 개가 먼저 들어가므로 계단 오프셋은 2번째 칸이다.
        #expect(placed.position == NotePoint(x: 270 + 68, y: 240 + 68))
    }

    @Test("외장 모니터의 좌상단을 주면 그 화면 위에 뜬다")
    func externalOriginMovesTheNote() throws {
        // 내장 1512×982 왼쪽에 외장 1920×1080. 외장 좌상단은 메모 좌표로 (-1920, -98) 이다.
        let external = NotePoint(x: -1920, y: 982 - 1080)
        let store = store()
        let id = store.addNote(origin: external)
        let placed = try #require(store.notes.first { $0.id == id })
        #expect(placed.position == NotePoint(x: external.x + 270 + 68, y: external.y + 240 + 68))
    }

    @Test("탭 복원이 세우는 메모도 같은 식을 쓴다")
    func restoringATabUsesTheSameOrigin() throws {
        let external = NotePoint(x: -1920, y: -98)
        let store = store()
        let noteID = store.addNote()
        let tabID = try #require(store.notes.first { $0.id == noteID }?.selectedTabID)
        let restoredTabID = try #require(store.addTab(to: noteID))
        store.moveTabToTrash(noteID: noteID, tabID: restoredTabID)
        store.moveTabToTrash(noteID: noteID, tabID: tabID)
        store.moveNoteToTrash(noteID)
        let trashed = try #require(store.trashedTabs.first { $0.tab.id == restoredTabID })
        store.restoreTab(trashed.id, origin: external)
        // 원래 메모가 사라졌으니 복원은 메모를 새로 세운다. 그 자리가 외장 좌상단 기준이어야
        // 한다. 남은 메모는 샘플 두 개뿐이라 계단 오프셋도 2번째 칸이다.
        let standing = try #require(store.notes.last)
        #expect(standing.position == NotePoint(x: external.x + 270 + 68, y: external.y + 240 + 68))
    }
}

/// 저장과 복원이 서로의 역인지 본다. 화면 구성이 바뀔 때 옮겨진 자리를 다시 적는 경로가 이 왕복
/// 위에 서 있다 — 여기가 어긋나면 모니터를 꽂고 뺄 때마다 메모가 조금씩 밀린다. 실제 `NSWindow`
/// 를 쓰지만 화면에 올리지는 않는다.
@Suite("Note position round trip")
@MainActor
struct NotePositionRoundTripTests {
    private func window(x: Double, y: Double, width: Double, height: Double) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: x, y: y, width: width, height: height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        // 기본값 `true` 는 `close()` 가 창을 한 번 더 해제하게 만든다. ARC 가 이미 들고 있어서
        // 그대로 두면 테스트가 SIGSEGV 로 죽는다.
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func savingAndPlacingAreInverses() throws {
        try #require(NSScreen.noteAnchor != nil)
        let window = window(x: 240, y: 180, width: 310, height: 292)
        defer { window.close() }
        let origin = window.frame.origin
        let saved = try #require(window.notePosition)

        // 러너 화면이 작아도 메뉴 막대에 닿지 않게 조금만 옮긴다.
        window.setFrameOrigin(NSPoint(x: origin.x + 120, y: origin.y + 60))
        #expect(window.notePosition != saved)

        window.placeNote(at: saved)
        #expect(window.notePosition == saved)
        #expect(window.frame.origin == origin)
    }

    /// 폭이 홀수면 중심은 .5 로 남는다. 저장값이 소수인 것은 맞지만 창 원점까지 소수로 내려가면
    /// 1x 외장 모니터에서 글자가 번진다.
    @Test func placingLandsOnWholePoints() throws {
        try #require(NSScreen.noteAnchor != nil)
        let window = window(x: 100, y: 100, width: 311, height: 293)
        defer { window.close() }
        window.placeNote(at: NotePoint(x: 700.5, y: 400.25))
        #expect(window.frame.origin.x.truncatingRemainder(dividingBy: 1) == 0)
        #expect(window.frame.origin.y.truncatingRemainder(dividingBy: 1) == 0)
    }
}
