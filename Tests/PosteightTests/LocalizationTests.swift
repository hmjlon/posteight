import Foundation
import Testing
@testable import Posteight

@Suite("Localization")
struct LocalizationTests {
    @Test("한국어는 키를 그대로 돌려주고 영어는 표를 탄다")
    func lookupPerLanguage() {
        #expect(L("휴지통", language: .korean) == "휴지통")
        #expect(L("휴지통", language: .english) == "Trash")
    }

    @Test("표에 없는 키는 한국어 원문으로 떨어진다")
    func missingKeyFallsBackToKorean() {
        #expect(L("표에 없는 문장", language: .english) == "표에 없는 문장")
    }

    @Test("환경변수가 시스템 언어를 덮어써서 CI 러너를 재현할 수 있다")
    func systemLanguageOverride() {
        // 개발 맥이 한국어여도 영어 러너를 흉내낼 수 있어야 한다. 이게 안 되면
        // 로케일 버그는 푸시하기 전까지 드러나지 않는다.
        #expect(AppLanguage.systemLanguage(override: "en", preferred: "ko-KR") == .english)
        #expect(AppLanguage.systemLanguage(override: "ko", preferred: "en-US") == .korean)
    }

    @Test("덮어쓰기가 없거나 읽을 수 없으면 기계 설정으로 떨어진다")
    func systemLanguageFallback() {
        #expect(AppLanguage.systemLanguage(override: nil, preferred: "ko-KR") == .korean)
        #expect(AppLanguage.systemLanguage(override: nil, preferred: "en-US") == .english)
        // 알 수 없는 태그는 언어를 강제하지 않고 다음 후보로 넘어간다.
        #expect(AppLanguage.systemLanguage(override: "zz", preferred: "ko-KR") == .korean)
        #expect(AppLanguage.systemLanguage(override: nil, preferred: nil) == .english)
    }

    @Test("resolved 는 .system 을 절대 돌려주지 않는다")
    func resolvedIsAlwaysConcrete() {
        for language in AppLanguage.allCases {
            #expect(language.resolved != .system)
        }
    }

    @Test("모든 영어 번역은 비어 있지 않고 한국어와 다르다")
    func everyTranslationIsRealAndDifferent() {
        for key in StringTable.englishKeys {
            let english = try! #require(StringTable.english(key))
            #expect(!english.trimmingCharacters(in: .whitespaces).isEmpty, "빈 번역: \(key)")
            #expect(english != key, "번역되지 않은 키: \(key)")
        }
    }

    /// `%d`/`%@` 자리 개수가 어긋나면 `String(format:)` 이 조용히 쓰레기를 낸다.
    @Test("서식 문자열의 자리표시자 개수가 두 언어에서 같다")
    func formatSpecifiersMatch() {
        for key in StringTable.englishKeys where key.contains("%") {
            let english = try! #require(StringTable.english(key))
            #expect(
                key.components(separatedBy: "%").count == english.components(separatedBy: "%").count,
                "자리표시자 개수 불일치: \(key) → \(english)"
            )
        }
    }

    @Test("서식 헬퍼가 두 언어에서 값을 채운다")
    func formatting() {
        #expect(Lf("메모 %d", language: .korean, 3) == "메모 3")
        #expect(Lf("메모 %d", language: .english, 3) == "Memo 3")
        #expect(Lf("탭 %d개 · 할 일 %d개", language: .english, 2, 5) == "2 tabs · 5 items")
    }

    @Test("일일 기록이 영어로 나온다")
    func dailyLogInEnglish() {
        let notes = [
            StickyNote(
                stickerSymbol: "tag",
                paperHex: "#FFFFFF",
                penHex: "#000000",
                includeInNotionLog: true,
                position: NotePoint(x: 0, y: 0),
                tabs: [MemoTab(name: "Memo 1", title: "Today", items: [TodoItem(title: "ship it")])]
            )
        ]
        let markdown = PosteightStore.dailyLogMarkdown(notes: notes, language: .english)

        #expect(markdown.contains("Work Log"))
        #expect(markdown.contains("### Memo 1 · Done"))
        #expect(markdown.contains("### Memo 1 · Remaining"))
        #expect(markdown.contains("- None"))
    }

    @Test("비어 있는 탭 이름은 읽는 언어로 메꿔진다")
    func blankTabNameIsFilledInReadingLanguage() throws {
        let note = StickyNote(
            stickerSymbol: "tag",
            paperHex: "#FFFFFF",
            penHex: "#000000",
            includeInNotionLog: false,
            position: NotePoint(x: 0, y: 0),
            tabs: [MemoTab(name: "   ", title: "", items: [])]
        )

        #expect(PosteightStore.compacted([note], language: .english)[0].tabs[0].name == "Memo 1")
        #expect(PosteightStore.compacted([note], language: .korean)[0].tabs[0].name == "메모 1")
    }

    /// 스토어가 `AppSettings.shared` 를 몰래 읽던 시절, 새 탭 이름이 기계의 시스템 언어를
    /// 따라가서 한국어 맥에서는 통과하고 영어 CI 에서는 깨졌다. 두 언어를 다 못 박는다.
    @Test @MainActor
    func newTabNamesFollowTheLanguagePassedIn() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let store = PosteightStore(directory: directory)
        let korean = store.addNote(language: .korean)
        let english = store.addNote(language: .english)

        #expect(try tabNames(store, korean) == ["메모 1"])
        #expect(try tabNames(store, english) == ["Memo 1"])

        _ = store.addTab(to: korean, language: .korean)
        _ = store.addTab(to: english, language: .english)

        #expect(try tabNames(store, korean) == ["메모 1", "메모 2"])
        #expect(try tabNames(store, english) == ["Memo 1", "Memo 2"])
    }

    /// 언어를 넘기지 않으면 소스 언어인 한국어다. 기존 테스트가 기대는 계약이라, 여기가
    /// 흔들리면 `PersistenceTests` 전체가 기계 설정을 타기 시작한다.
    @Test @MainActor
    func omittingTheLanguageMeansKorean() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let store = PosteightStore(directory: directory)
        #expect(try tabNames(store, store.addNote()) == ["메모 1"])
    }

    @MainActor
    private func tabNames(_ store: PosteightStore, _ noteID: UUID) throws -> [String] {
        try #require(store.notes.first { $0.id == noteID }).tabs.map(\.name)
    }

    /// 옛 빌드가 디스크에 쓴 문자열과 비교하는 자리라, 번역되면 마이그레이션이 통째로 끊긴다.
    @Test("레거시 제목 마이그레이션은 언어와 무관하게 동작한다")
    func legacyTitleMigrationIsLanguageIndependent() throws {
        let note = StickyNote(
            stickerSymbol: "tag",
            paperHex: "#FFFFFF",
            penHex: "#000000",
            includeInNotionLog: false,
            position: NotePoint(x: 0, y: 0),
            tabs: [MemoTab(name: "n", title: "새 포스트잇", items: [])]
        )

        for language in [AppLanguage.korean, .english] {
            let migrated = PosteightStore.compacted([note], language: language)[0]
            #expect(migrated.tabs[0].title == PosteightStore.todayTitle(language: language))
        }
    }
}
