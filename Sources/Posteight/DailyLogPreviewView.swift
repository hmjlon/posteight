import SwiftUI

struct DailyLogPreviewView: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("오늘 기록"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                Spacer()

                Button {
                    store.copyDailyLogToClipboard()
                } label: {
                    Label(L("Markdown 복사"), systemImage: "doc.on.doc")
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            Text(L("Notion 기록이 켜진 메모만 정리됩니다."))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(store.dailyLogMarkdown())
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor), in: Rectangle())
            .overlay {
                Rectangle()
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            }
        }
        .padding(18)
        .frame(width: 560, height: 520)
        .navigationTitle(L("오늘 기록"))
    }
}
