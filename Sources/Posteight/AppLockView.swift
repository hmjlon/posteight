import AppKit
import SwiftUI

/// Content is removed, rather than blurred or covered, so it is absent from accessibility too.
struct AppLockGate<Content: View>: View {
    @ObservedObject private var lock = AppLock.shared
    @ObservedObject private var settings = AppSettings.shared
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if lock.isLocked {
                LockedContentView()
            } else {
                content()
            }
        }
        .onAppear { if lock.isLocked { AppUnlockWindow.present() } }
    }
}

struct LockedContentView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(L("Posteight이 잠겨 있어요"))
                .font(.system(size: 13, weight: .medium))
            Button(L("잠금 해제")) { AppUnlockWindow.present() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

@MainActor
enum AppUnlockWindow {
    private static var window: NSWindow?

    static func present() {
        guard AppLock.shared.isLocked else { return }
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = NSHostingController(rootView: UnlockView())
        let window = NSWindow(contentViewController: controller)
        window.title = L("잠금 해제")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        Self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func dismiss() {
        window?.close()
        window = nil
    }
}

private struct UnlockView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isAuthenticating = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "touchid")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(L("Posteight이 잠겨 있어요")).font(.headline)
            Text(L("Touch ID 또는 Mac 로그인 암호로 잠금을 해제해요."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error { Text(L(error)).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L("취소")) { AppUnlockWindow.dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L(isAuthenticating ? "본인 확인 중…" : "잠금 해제"), action: unlock)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAuthenticating)
            }
        }
        .padding(24)
        .frame(width: 300)
    }

    private func unlock() {
        isAuthenticating = true
        error = nil
        Task { @MainActor in
            defer { isAuthenticating = false }
            do {
                try await AppLock.shared.unlock()
                AppUnlockWindow.dismiss()
            } catch let failure as AppLock.Failure {
                error = failure.messageKey
            } catch {
                self.error = "Mac에서 본인 확인을 완료하지 못했어요."
            }
        }
    }
}

struct AppLockSettingsSection: View {
    @ObservedObject private var lock = AppLock.shared
    @State private var mode: AuthenticationMode?

    var body: some View {
        Section(L("앱 잠금")) {
            Toggle(L("앱 잠금 사용"), isOn: Binding(
                get: { lock.isEnabled },
                set: { mode = $0 ? .enable : .disable }
            ))
            Text(L("Touch ID 또는 Mac 로그인 암호로 잠금을 해제할 수 있어요. 메뉴 막대에서 앱 전체를 잠그고, 다시 실행하면 잠긴 상태로 시작해요."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .sheet(item: $mode) { mode in
            AuthenticationSettingsView(mode: mode)
        }
    }
}

private enum AuthenticationMode: String, Identifiable {
    case enable, disable
    var id: String { rawValue }
    var title: String { self == .enable ? "앱 잠금 사용" : "앱 잠금 끄기" }
    var explanation: String {
        self == .enable
            ? "Touch ID 또는 Mac 로그인 암호로 본인 확인 후 앱 잠금을 사용해요."
            : "Touch ID 또는 Mac 로그인 암호로 본인 확인 후 앱 잠금을 꺼요."
    }
}

private struct AuthenticationSettingsView: View {
    let mode: AuthenticationMode
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthenticating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L(mode.title)).font(.headline)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "touchid")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
                Text(L(mode.explanation))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(L("이 기능은 화면을 잠그며 저장된 메모를 암호화하지는 않아요."))
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(L(error)).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L("취소")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L(isAuthenticating ? "본인 확인 중…" : "계속"), action: authenticate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAuthenticating)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func authenticate() {
        isAuthenticating = true
        error = nil
        Task { @MainActor in
            defer { isAuthenticating = false }
            do {
                switch mode {
                case .enable: try await AppLock.shared.enable()
                case .disable: try await AppLock.shared.disable()
                }
                dismiss()
            } catch let failure as AppLock.Failure {
                error = failure.messageKey
            } catch {
                self.error = "Mac에서 본인 확인을 완료하지 못했어요."
            }
        }
    }
}
