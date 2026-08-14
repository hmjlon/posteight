import Foundation
import Testing

@testable import Posteight

// The store itself talks to disk and UserDefaults, so these cover the pure logic it runs on
// loaded data: title migration (which can silently rewrite a user's notes), size clamping,
// and the daily log the Notion export will be built on.

private func note(
    title: String = "메모",
    includeInNotionLog: Bool = true,
    size: NoteSize = DesignTokens.defaultNoteSize,
    items: [TodoItem] = []
) -> StickyNote {
    StickyNote(
        title: title,
        stickerSymbol: "tag",
        paperHex: "#FADDE5",
        penHex: "#B84A62",
        includeInNotionLog: includeInNotionLog,
        position: NotePoint(x: 0, y: 0),
        size: size,
        items: items
    )
}

@Suite("Legacy title migration")
struct LegacyTitleTests {
    @Test("Four-digit-year titles are recognised and keep their own date")
    func migratesLegacyTitle() throws {
        let date = try #require(PosteightStore.legacyTitleDate("2025.03.14"))

        var components = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone.current
        let parts = components.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2025)
        #expect(parts.month == 3)
        #expect(parts.day == 14)

        #expect(PosteightStore.compacted([note(title: "2025.03.14")])[0].title == "25.03.14(금)")
    }

    @Test("Titles already in the short style are left alone")
    func keepsCurrentStyleTitle() {
        #expect(PosteightStore.legacyTitleDate("25.03.14(금)") == nil)
        #expect(PosteightStore.compacted([note(title: "25.03.14(금)")])[0].title == "25.03.14(금)")
    }

    @Test("A title the user typed is never treated as a date")
    func keepsUserTitle() {
        #expect(PosteightStore.legacyTitleDate("오늘 업무") == nil)
        #expect(PosteightStore.compacted([note(title: "오늘 업무")])[0].title == "오늘 업무")
    }

    @Test("The old placeholder title becomes today")
    func replacesPlaceholderTitle() {
        let migrated = PosteightStore.compacted([note(title: "새 포스트잇")])
        #expect(migrated[0].title == PosteightStore.todayTitle())
    }
}

@Suite("Note size clamping")
struct ClampTests {
    @Test("Sizes below the minimum are raised")
    func clampsSmall() {
        let clamped = PosteightStore.clamped(NoteSize(width: 10, height: 10))
        #expect(clamped == DesignTokens.minimumNoteSize)
    }

    @Test("Sizes above the maximum are lowered")
    func clampsLarge() {
        let clamped = PosteightStore.clamped(NoteSize(width: 9_999, height: 9_999))
        #expect(clamped == DesignTokens.maximumNoteSize)
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
    private let date = Date(timeIntervalSince1970: 1_741_910_400)  // 2025-03-14 UTC

    @Test("Only notes flagged for the log are included")
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

    @Test("Done and pending items are split")
    func splitsByCompletion() {
        let markdown = PosteightStore.dailyLogMarkdown(
            notes: [
                note(items: [
                    TodoItem(title: "끝난 일", isDone: true, completedAt: date),
                    TodoItem(title: "남은 일")
                ])
            ],
            date: date
        )

        let done = try? #require(markdown.range(of: "### 완료한 일"))
        let pending = try? #require(markdown.range(of: "### 남은 일"))
        #expect(done != nil && pending != nil)
        #expect(markdown.contains("- 끝난 일"))
        #expect(markdown.contains("- 남은 일"))
        // "끝난 일" must sit in the done section, before the pending heading.
        #expect(markdown.range(of: "- 끝난 일")!.lowerBound < pending!.lowerBound)
        #expect(markdown.range(of: "- 남은 일")!.lowerBound > pending!.lowerBound)
    }

    @Test("An empty section says so instead of leaving a bare heading")
    func marksEmptySections() {
        let markdown = PosteightStore.dailyLogMarkdown(
            notes: [note(items: [TodoItem(title: "남은 일")])],
            date: date
        )

        #expect(markdown.contains("### 완료한 일\n- 없음"))
    }

    @Test("No flagged notes produces a readable message, not an empty document")
    func handlesNoFlaggedNotes() {
        let markdown = PosteightStore.dailyLogMarkdown(
            notes: [note(includeInNotionLog: false)],
            date: date
        )

        #expect(markdown.contains("Notion 기록에 포함된 포스트잇이 없습니다."))
    }
}
