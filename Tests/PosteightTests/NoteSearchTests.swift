import Foundation
import Testing
@testable import Posteight

@Suite("전체 메모 검색")
struct NoteSearchTests {
    private func note(_ tabs: [MemoTab]) -> StickyNote {
        StickyNote(stickerSymbol: "tag", paperHex: "FFFFFF", penHex: "000000",
                   position: NotePoint(x: 0, y: 0), tabs: tabs)
    }

    @Test("선택하지 않은 탭과 다른 메모, 완료 항목 및 세부사항도 검색한다")
    func searchesAllContent() {
        let first = note([
            MemoTab(name: "첫 탭", title: "", items: []),
            MemoTab(name: "업무", title: "", items: [
                TodoItem(title: "회의 준비", isDone: true),
                TodoItem(title: "참고", detail: "지난 회의 의견")
            ])
        ])
        let second = note([MemoTab(name: "회의 기록", title: "", items: [])])
        let results = NoteSearch.results(in: [first, second], query: "회의")
        #expect(results.count == 2)
        #expect(results.first?.noteID == second.id)
        #expect(results.last?.tab.id == first.tabs[1].id)
        #expect(results.last?.matchingItems.count == 2)
        #expect(results.last?.matchingItems.first?.isDone == true)
    }

    @Test("부분 일치와 영문 대소문자, 앞뒤 공백을 처리한다")
    func matching() {
        let notes = [note([MemoTab(name: "업무", title: "SwiftUI 공부", items: [])])]
        #expect(NoteSearch.results(in: notes, query: "  swift\n").count == 1)
        #expect(NoteSearch.results(in: notes, query: " \n").isEmpty)
        #expect(NoteSearch.results(in: notes, query: "없는 단어").isEmpty)
        #expect(NoteSearch.results(in: [], query: "Swift").isEmpty)
    }

    @Test("검색 결과를 중복하지 않고 원본 순서를 유지한다")
    func groupingAndOrder() {
        let tabs = [
            MemoTab(name: "회의 A", title: "회의", items: [TodoItem(title: "회의")]),
            MemoTab(name: "회의 B", title: "", items: [])
        ]
        let notes = [note(tabs)]
        let original = notes
        #expect(NoteSearch.results(in: notes, query: "회의").map(\.tab.id) == tabs.map(\.id))
        #expect(notes == original)
    }

    @Test("강조 범위는 반복되는 한글과 대소문자가 다른 영문을 모두 찾는다")
    func highlights() {
        let text = "회의 후 회의, Swift swift"
        #expect(NoteSearch.ranges(in: text, query: "회의").map { String(text[$0]) } == ["회의", "회의"])
        #expect(NoteSearch.ranges(in: text, query: "SWIFT").count == 2)
        #expect(NoteSearch.ranges(in: text, query: " ").isEmpty)
    }
}
