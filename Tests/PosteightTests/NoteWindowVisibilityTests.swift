import AppKit
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

/// `sharingType` is what keeps memo text out of screen shares, and it is a per-NSWindow property
/// that child windows do not inherit — every popover and sheet needs its own.
@Suite("Screen capture exclusion")
@MainActor
struct ScreenCaptureExclusionTests {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
                 styleMask: [.titled], backing: .buffered, defer: false)
    }

    /// The old code applied the exclusion after a single `DispatchQueue.main.async` hop. When the
    /// view had no window yet at that moment, optional chaining swallowed it with no log and the
    /// window stayed capturable unless `updateNSView` happened to run again.
    @Test("A view that joins its window later is still excluded")
    func exclusionSurvivesALateWindow() {
        let view = SharingTypeView()
        view.sharingType = .none
        #expect(view.window == nil)

        let host = window()
        host.sharingType = .readOnly
        host.contentView?.addSubview(view)

        #expect(view.window === host)
        #expect(host.sharingType == .none)
    }

    @Test("Turning the setting off puts the window back in the capture")
    func exclusionFollowsTheSetting() {
        let host = window()
        let view = SharingTypeView()
        host.contentView?.addSubview(view)

        view.sharingType = .none
        #expect(host.sharingType == .none)
        view.sharingType = .readOnly
        #expect(host.sharingType == .readOnly)
    }

    /// Moving between windows must not leave the new one capturable.
    @Test("Re-parenting carries the exclusion to the new window")
    func exclusionFollowsTheView() {
        let first = window()
        let second = window()
        second.sharingType = .readOnly

        let view = SharingTypeView()
        first.contentView?.addSubview(view)
        view.sharingType = .none

        view.removeFromSuperview()
        second.contentView?.addSubview(view)
        #expect(second.sharingType == .none)
    }

    /// The setting drives both windows and popovers from one place.
    @Test("The setting maps to the two sharing types")
    func settingMapsToSharingType() {
        let settings = AppSettings.shared
        let previous = settings.hidesNotesFromScreenCapture
        defer { settings.hidesNotesFromScreenCapture = previous }

        settings.hidesNotesFromScreenCapture = true
        #expect(settings.noteWindowSharingType == .none)
        settings.hidesNotesFromScreenCapture = false
        #expect(settings.noteWindowSharingType == .readOnly)
    }
}
