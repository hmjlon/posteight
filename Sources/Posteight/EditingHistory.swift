import SwiftUI

struct EditingSnapshot: Equatable {
    var notes: [StickyNote]
    var trashedNotes: [TrashedStickyNote]
    var trashedTabs: [TrashedMemoTab]
}

struct EditingHistoryEntry {
    enum Change {
        case data(before: EditingSnapshot, after: EditingSnapshot)
        case closedWindow(UUID)
    }
    var change: Change
    var key: String?
    var noteID: UUID?
    var tabID: UUID?
}

struct HistoryWindowRequest: Equatable {
    let id = UUID()
    let noteID: UUID
    let show: Bool
}

private struct EditingStoreKey: EnvironmentKey {
    static let defaultValue: PosteightStore? = nil
}

extension EnvironmentValues {
    var editingStore: PosteightStore? {
        get { self[EditingStoreKey.self] }
        set { self[EditingStoreKey.self] = newValue }
    }
}
