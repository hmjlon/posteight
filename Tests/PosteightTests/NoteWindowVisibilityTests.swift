import Foundation
import Testing
@testable import Posteight

@Suite("Note window visibility")
struct NoteWindowVisibilityTests {
    @Test("한 메모만 숨김 상태로 표시한다")
    func hidingOneMemoKeepsItsIdentity() {
        let hiddenID = UUID()
        let visibleID = UUID()
        var visibility = NoteWindowVisibility()

        visibility.hide(hiddenID)

        #expect(visibility.isHidden(hiddenID))
        #expect(!visibility.isHidden(visibleID))
    }

    @Test("등록된 메모와 생성 중인 메모를 모두 숨긴다")
    func hideAllIncludesPendingWindows() {
        let registeredID = UUID()
        let pendingID = UUID()
        var visibility = NoteWindowVisibility()

        visibility.hideAll(registered: [registeredID], pending: [pendingID])

        #expect(visibility.isHidden(registeredID))
        #expect(visibility.isHidden(pendingID))
    }

    @Test("다시 표시한 메모만 숨김 상태에서 제외한다")
    func presentingOneMemoKeepsTheOthersHidden() {
        let firstID = UUID()
        let secondID = UUID()
        var visibility = NoteWindowVisibility()
        visibility.hideAll(registered: [firstID, secondID], pending: [])

        visibility.present(firstID)

        #expect(!visibility.isHidden(firstID))
        #expect(visibility.isHidden(secondID))
    }

    @Test("화면을 풀면 잠금이 감춘 메모만 되돌리고 사용자가 숨긴 것은 그대로 둔다")
    func unlockRestoresOnlyWhatTheLockHid() {
        let lockedID = UUID()
        let userHiddenID = UUID()
        var visibility = NoteWindowVisibility()
        visibility.hide(userHiddenID)

        let restorable = visibility.restorableAfterLock([lockedID, userHiddenID])

        #expect(restorable == [lockedID])
    }
}
