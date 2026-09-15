import Combine
import Foundation
import LocalAuthentication

/// A local screen lock backed by the Mac's owner authentication.
/// Notes remain in their existing storage format, and Posteight stores no password.
@MainActor
final class AppLock: ObservableObject {
    typealias Authenticator = @MainActor (_ reason: String) async throws -> Void

    static let shared = AppLock()
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
