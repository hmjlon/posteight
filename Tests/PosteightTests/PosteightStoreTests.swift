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

    @Test("Blank tab names receive a local default name")
    func fillsBlankTabName() throws {
        let migrated = PosteightStore.compacted([note(tabName: "   ")])
        #expect(try firstTab(migrated[0]).name == "메모 1")
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
        #expect(markdown.contains("## 포함"))
        #expect(!markdown.contains("## 제외"))
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
        let done = try #require(markdown.range(of: "### 메모 1 · 완료한 일"))
        let pending = try #require(markdown.range(of: "### 메모 1 · 남은 일"))
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
        #expect(markdown.contains("### 메모 1 · 완료한 일\n- 없음"))
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
}
