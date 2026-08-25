import AppKit
import SwiftUI

/// Deliberately small: only the choices that change how Posteight sits on the desktop.
struct SettingsView: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var settings = AppSettings.shared

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            form

            Divider()

            HStack {
                Spacer()

                Button("완료", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 440, height: 500)
    }

    private var form: some View {
        Form {
            Section("메뉴 막대") {
                Picker("표시 방식", selection: $settings.menuBarCountStyle) {
                    ForEach(MenuBarCountStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)

                LabeledContent("미리보기") {
                    Text(preview)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Section("노트") {
                Toggle("노트를 항상 맨 앞에 표시", isOn: $settings.keepsNotesOnTop)
                Text("끄면 다른 앱 뒤로 밀려나서, 집중해서 일할 때 화면을 덜 가립니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("앱") {
                Toggle("Dock 아이콘 표시", isOn: $settings.showsDockIcon)
                Text("끄면 메뉴 막대에서만 실행됩니다. Dock 아이콘을 누르면 모든 노트가 다시 열립니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                LabeledContent("노트 저장 위치") {
                    Button("폴더 열기") {
                        NSWorkspace.shared.activateFileViewerSelecting([PosteightStore.storeDirectory])
                    }
                }
            }

            Section {
                LabeledContent("버전", value: versionLabel)
            }
        }
        .formStyle(.grouped)
    }

    private var preview: String {
        let count = settings.menuBarCountStyle == .done ? store.doneCount : store.remainingCount
        return "\(count)/\(store.totalCount)"
    }

    private var versionLabel: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "개발 빌드"
        }

        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
