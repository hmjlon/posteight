import Combine
import Foundation
import LocalAuthentication

/// A local screen lock backed by the Mac's owner authentication.
/// Notes remain in their existing storage format, and Posteight stores no password.
@MainActor
final class AppLock: ObservableObject {
    typealias Authenticator = @MainActor (_ reason: String) async throws -> Void

    static let shared = AppLock()

    /// 잠금 사용 여부의 유일한 근거다. **이 값은 인증으로 지켜지지 않는다.**
    ///
    /// 샌드박스 컨테이너 안에 있지만 같은 사용자로 도는 아무 프로세스나 양방향으로 뒤집을 수
    /// 있다(`defaults write com.younjiyoung.posteight posteight.appLock.isEnabled -bool
    /// false`). 아래 `enable`/`disable` 의 본인 확인은 이 앱이 값을 바꾸기 *전에* 자발적으로
    /// 부르는 것일 뿐, 값 자체를 지키지는 못한다.
    ///
    /// 제대로 막으려면 `SecAccessControl(.userPresence)` 로 보호되는 Keychain 항목으로
    /// 옮겨야 하는데, 그건 data protection keychain 을 요구하고 그 키체인은
    /// `application-identifier`(또는 `keychain-access-groups`) entitlement 를 요구한다.
    /// 지금은 Team ID 없는 ad-hoc 서명이라 그 entitlement 가 붙지 않고, 샌드박스 + ad-hoc
    /// 로 재현한 번들에서 `SecItemAdd` 가 실제로 `-34018 errSecMissingEntitlement` 로
    /// 떨어지는 것을 확인했다. 인증 게이트 없는 평문 Keychain 항목으로 옮기는 것은 의미가
    /// 없다 — 같은 번들에서 쓴 항목을 무관한 프로세스가 프롬프트 0회로 읽고 지웠다.
    ///
    /// 그래서 지금은 설정 화면에서 고지만 한다(`AppLockView`). 배포 서명이 들어오면
    /// (`.handoff/SECURITY-HANDOFF.md` 의 WP-5) 그때 Keychain 으로 옮긴다.
    static let enabledKey = "posteight.appLock.isEnabled"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isLocked: Bool
    private let defaults: UserDefaults
    private let authenticateOwner: Authenticator

    init(
        defaults: UserDefaults = .standard,
        authenticateOwner: @escaping Authenticator = AppLock.authenticateWithSystem
    ) {
        self.defaults = defaults
        self.authenticateOwner = authenticateOwner
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    func enable() async throws {
        guard !isEnabled else { return }
        try await authenticateOwner(L("앱 잠금을 사용하려면 본인 확인이 필요해요."))
        defaults.set(true, forKey: Self.enabledKey)
        isEnabled = true
    }

    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }

    func unlock() async throws {
        guard isEnabled, isLocked else { return }
        try await authenticateOwner(L("Posteight의 잠금을 해제해 주세요."))
        isLocked = false
    }

    func disable() async throws {
        guard isEnabled else { return }
        try await authenticateOwner(L("앱 잠금을 끄려면 본인 확인이 필요해요."))
        defaults.removeObject(forKey: Self.enabledKey)
        isEnabled = false
        isLocked = false
    }

    private static func authenticateWithSystem(reason: String) async throws {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            throw Failure.unavailable
        }

        do {
            let authenticated = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            guard authenticated else { throw Failure.authenticationFailed }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                throw Failure.cancelled
            case .biometryNotAvailable, .passcodeNotSet, .notInteractive:
                throw Failure.unavailable
            default:
                throw Failure.authenticationFailed
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.authenticationFailed
        }
    }

    enum Failure: Error {
        case authenticationFailed, unavailable, cancelled

        var messageKey: String? {
            switch self {
            case .authenticationFailed: "Mac에서 본인 확인을 완료하지 못했어요."
            case .unavailable: "이 Mac에서 본인 확인을 사용할 수 없어요."
            case .cancelled: nil
            }
        }
    }
}
