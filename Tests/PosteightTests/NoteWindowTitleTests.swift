import Foundation
import Testing
@testable import Posteight

@Suite("Note window title")
struct NoteWindowTitleTests {
    @Test("잠겨 있으면 앱 이름만 내보낸다")
    func lockedWindowExposesOnlyTheAppName() {
        #expect(NoteWindowTitle.make(isLocked: true, tabName: "장보기 목록") == "Posteight")
    }

    @Test("잠겨 있지 않으면 탭 이름을 내보낸다")
    func unlockedWindowExposesTheTabName() {
        #expect(NoteWindowTitle.make(isLocked: false, tabName: "메모 1") == "메모 1")
    }

    @Test("이름이 비어 있으면 앱 이름으로 떨어진다")
    func blankTabNameFallsBackToTheAppName() {
        #expect(NoteWindowTitle.make(isLocked: false, tabName: "") == "Posteight")
        #expect(NoteWindowTitle.make(isLocked: false, tabName: "   \n ") == "Posteight")
    }

    /// 창 제목은 `kCGWindowName`·Mission Control·Window 메뉴로 나가고, 화면 캡처 제외는 그
    /// 경로를 막지 못한다. 그래서 사용자가 쓴 본문 제목은 어떤 상태에서도 나가면 안 된다.
    @Test("사용자가 쓴 본문 제목은 어느 경로로도 창 제목이 되지 않는다")
    func theUserWrittenTitleNeverReachesTheWindowTitle() {
        let tab = MemoTab(name: "메모 1", title: "건강검진 결과 정리")

        for isLocked in [true, false] {
            let title = NoteWindowTitle.make(isLocked: isLocked, tabName: tab.name)
            #expect(title != tab.title)
        }
    }
}
