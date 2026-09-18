import Foundation

enum StorageFailure: Error, Equatable {
    case read, save, migration

    var messageKey: String {
        switch self {
        case .read: "저장된 메모를 읽지 못했어요. 원본을 보호하기 위해 편집과 저장을 멈췄어요."
        case .save: "메모를 저장하지 못했어요. 저장 공간과 폴더 권한을 확인한 뒤 다시 시도해 주세요."
        case .migration: "이전 메모를 가져오지 못했어요. 원본은 그대로 있어요. 저장 폴더를 확인한 뒤 다시 시도해 주세요."
        }
    }
}

/// Notes and both trash collections travel together. Settings and font files are not included.
struct StoreBackup: Codable {
    var formatVersion = 1
    var createdAt = Date()
    let notes: [StickyNote]
    let trashedNotes: [TrashedStickyNote]
    let trashedTabs: [TrashedMemoTab]

    func validate() throws {
        guard formatVersion == 1,
              Set(notes.map(\.id)).count == notes.count,
              Set(trashedNotes.map(\.id)).count == trashedNotes.count,
              Set(trashedTabs.map(\.id)).count == trashedTabs.count else { throw StorageFailure.read }
        for note in notes + trashedNotes.map(\.note) {
            guard Set(note.tabs.map(\.id)).count == note.tabs.count,
                  note.position.x.isFinite, note.position.y.isFinite,
                  note.size.width.isFinite, note.size.height.isFinite else { throw StorageFailure.read }
            for tab in note.tabs {
                guard Set(tab.items.map(\.id)).count == tab.items.count else { throw StorageFailure.read }
            }
        }
        for entry in trashedTabs {
            guard Set(entry.tab.items.map(\.id)).count == entry.tab.items.count else { throw StorageFailure.read }
        }
    }
}
