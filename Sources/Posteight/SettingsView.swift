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

                Button(L("완료"), action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 440, height: 500)
        .navigationTitle(L("Posteight 설정"))
    }

    private var form: some View {
        Form {
            // Language sits first: someone who cannot read the current language has to be able
            // to find this row without understanding anything else on the screen.
            Section(L("언어")) {
                Picker(L("언어"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title(in: settings.language)).tag(language)
                    }
                }
                // A radio group reflows to a stack the moment the options outgrow the row, so
                // the window changed shape between languages. A pop-up is the same size in both.
                .pickerStyle(.menu)

                Text(L("Posteight 안에서만 바뀝니다. macOS 가 그리는 메뉴 막대 메뉴는 시스템 언어를 따릅니다."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section(L("메뉴 막대")) {
                Picker(L("표시 방식"), selection: $settings.menuBarCountStyle) {
                    ForEach(MenuBarCountStyle.allCases) { style in
                        Text(style.title(in: settings.language)).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)

                LabeledContent(L("미리보기")) {
                    MenuBarProgressCard(
                        done: store.doneCount,
                        total: store.totalCount,
                        count: previewCount
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section(L("노트")) {
                Toggle(L("노트를 항상 맨 앞에 표시"), isOn: $settings.keepsNotesOnTop)
                Text(L("끄면 다른 앱 뒤로 밀려나서, 집중해서 일할 때 화면을 덜 가립니다."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section(L("앱")) {
                Toggle(L("Dock 아이콘 표시"), isOn: $settings.showsDockIcon)
                Text(L("끄면 메뉴 막대에서만 실행됩니다. Dock 아이콘을 누르면 모든 노트가 다시 열립니다."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                LabeledContent(L("노트 저장 위치")) {
                    Button(L("폴더 열기")) {
                        NSWorkspace.shared.activateFileViewerSelecting([PosteightStore.storeDirectory])
                    }
                }
            }

            Section {
                LabeledContent(L("버전"), value: versionLabel)
            }
        }
        .formStyle(.grouped)
    }

    private var previewCount: Int {
        settings.menuBarCountStyle == .done ? store.doneCount : store.remainingCount
    }

    private var versionLabel: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return L("개발 빌드")
        }

        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
