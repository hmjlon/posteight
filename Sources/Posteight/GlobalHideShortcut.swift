import AppKit
import Carbon

/// ⌃⌥⌘H — 다른 앱을 쓰는 중에도 메모를 한 번에 숨기고 되돌린다. Carbon 전역 단축키는 권한이
/// 필요 없고 샌드박스에서도 된다.
///
/// 다른 앱이 같은 키를 쓰는지는 알아낼 수 없다. `RegisterEventHotKey` 는 두 앱이 모두
/// `kEventHotKeyExclusive` 로 등록할 때만 실패를 돌려주고, 한쪽이라도 일반 등록이면 둘 다
/// 성공한다(2026-10-08 두 프로세스로 직접 확인). 그래서 기본 키는 macOS 기본 단축키와 흔한 앱
/// 단축키가 쓰지 않는 ⌃⌥⌘ 조합으로 두고, 겹칠 때 끄는 스위치만 설정에 둔다.
@MainActor
enum GlobalHideShortcut {
    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    static func update(enabled: Bool) {
        if enabled { register() } else { unregister() }
    }

    private static func register() {
        guard hotKey == nil else { return }
        if handler == nil {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                        eventKind: UInt32(kEventHotKeyPressed))
            // 등록하는 키가 하나뿐이라 어느 키인지 가려낼 필요가 없다.
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                MainActor.assumeIsolated { NoteWindowCoordinator.shared.toggleFromShortcut() }
                return noErr
            }, 1, &pressed, nil, &handler)
        }
        // 물리 키 코드로 등록하므로 한글 입력 중에도 같은 키다.
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey | cmdKey),
                                         EventHotKeyID(signature: OSType(0x5038_4854), id: 1), // "P8HT"
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { NSLog("Posteight: global hide shortcut not registered: \(status)") }
    }

    private static func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}
