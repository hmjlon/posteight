import Foundation
import Testing
@testable import Posteight

@Suite @MainActor
struct AppLockTests {
    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let name = "PosteightTests.AppLock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    @Test func enableLockUnlockAndRelaunch() async throws {
        try await withDefaults { defaults in
            var reasons: [String] = []
            let lock = AppLock(defaults: defaults) { reasons.append($0) }

            #expect(!lock.isEnabled && !lock.isLocked)
            try await lock.enable()
            #expect(lock.isEnabled && !lock.isLocked)
            #expect(defaults.bool(forKey: AppLock.enabledKey))

            lock.lock()
            #expect(lock.isLocked)
            try await lock.unlock()
            #expect(!lock.isLocked)
            #expect(reasons.count == 2)

            let relaunched = AppLock(defaults: defaults) { _ in }
            #expect(relaunched.isEnabled && relaunched.isLocked)
        }
    }

    @Test func failedAuthenticationDoesNotChangeState() async {
        await withDefaults { defaults in
            let lock = AppLock(defaults: defaults) { _ in
                throw AppLock.Failure.authenticationFailed
            }

            do {
                try await lock.enable()
                Issue.record("인증 실패 후 잠금이 켜졌어요.")
            } catch {}
            #expect(!lock.isEnabled && !lock.isLocked)
            #expect(!defaults.bool(forKey: AppLock.enabledKey))

            defaults.set(true, forKey: AppLock.enabledKey)
            let enabledLock = AppLock(defaults: defaults) { _ in
                throw AppLock.Failure.authenticationFailed
            }
            do {
                try await enabledLock.unlock()
                Issue.record("인증 실패 후 잠금이 풀렸어요.")
            } catch {}
            #expect(enabledLock.isEnabled && enabledLock.isLocked)

            do {
                try await enabledLock.disable()
                Issue.record("인증 실패 후 잠금 설정이 꺼졌어요.")
            } catch {}
            #expect(enabledLock.isEnabled && enabledLock.isLocked)
            #expect(defaults.bool(forKey: AppLock.enabledKey))
        }
    }

    @Test func disableRequiresOwnerAuthentication() async throws {
        try await withDefaults { defaults in
            let lock = AppLock(defaults: defaults) { _ in }
            try await lock.enable()
            lock.lock()
            try await lock.disable()

            #expect(!lock.isEnabled && !lock.isLocked)
            #expect(defaults.object(forKey: AppLock.enabledKey) == nil)
            #expect(!AppLock(defaults: defaults) { _ in }.isEnabled)
        }
    }

    @Test func redundantOperationsDoNotRequestAuthentication() async throws {
        try await withDefaults { defaults in
            var authenticationCount = 0
            let lock = AppLock(defaults: defaults) { _ in authenticationCount += 1 }

            try await lock.unlock()
            try await lock.disable()
            #expect(authenticationCount == 0)

            try await lock.enable()
            try await lock.enable()
            #expect(authenticationCount == 1)
        }
    }
}
