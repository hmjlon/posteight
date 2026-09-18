import AppKit
import SwiftUI

struct StorageStatusView: View {
    @EnvironmentObject private var store: PosteightStore

    var body: some View {
        if let error = store.storageError {
            VStack(alignment: .leading, spacing: 8) {
                Label(L(error.messageKey), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button(L("다시 시도")) {
                    let wasMigration = store.storageError == .migration
                    if store.isStorageBlocked { store.retryLoading() }
                    else { store.flush() }
                    if wasMigration && !store.isStorageBlocked {
                        NoteFontLibrary.shared.reloadAfterMigration()
                    }
                }
            }
            .padding(8)
        }
    }
}

struct StorageRecoverySection: View {
    @EnvironmentObject private var store: PosteightStore
    @State private var confirmsRestore = false
    @State private var operationMessage: String?

    var body: some View {
        Section(L("저장과 백업")) {
            StorageStatusView()
            if let date = store.backupDate {
                LabeledContent(L("최근 백업")) { Text(date, format: .dateTime) }
            }
            HStack {
                Button(L("현재 메모 백업")) {
                    finishEditing()
                    do {
                        try store.createBackup()
                        operationMessage = "백업을 저장했어요."
                    } catch { operationMessage = "백업을 저장하지 못했어요. 저장 공간과 폴더 권한을 확인해 주세요." }
                }
                .disabled(store.isStorageBlocked)
                Button(L("백업 복원…")) { confirmsRestore = true }
                    .disabled(store.backupDate == nil || store.storageError == .migration)
            }
            Text(L("앱을 연 뒤 첫 저장 전에 이전 메모를 자동 백업해요. 직접 백업하면 기존 백업을 교체해요. 메모와 휴지통만 포함하며, 설정과 폰트 파일은 포함하지 않아요."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L("백업은 같은 Mac에 저장돼요. 복원 전 원본은 BeforeRestore 폴더에 보관하며, 필요 없어진 백업과 원본은 저장 폴더에서 직접 지울 수 있어요."))
                .font(.caption).foregroundStyle(.secondary)
            if let operationMessage { Text(L(operationMessage)).font(.caption) }
        }
        .confirmationDialog(L("백업으로 메모를 복원할까요?"), isPresented: $confirmsRestore) {
            Button(L("백업 복원"), role: .destructive) {
                finishEditing()
                do {
                    try store.restoreBackup()
                    operationMessage = "백업을 복원했어요."
                } catch { operationMessage = "백업을 복원하지 못했어요. 백업과 복원 전 원본은 저장 폴더에 보관되어 있어요." }
            }
            Button(L("취소"), role: .cancel) {}
        } message: {
            Text(L("현재 메모와 휴지통을 최근 백업으로 바꿉니다. 복원 전 파일은 별도로 보관하며, 복원은 실행 취소할 수 없어요."))
        }
    }

    private func finishEditing() {
        for window in NSApp.windows { window.makeFirstResponder(nil) }
    }
}
