import SwiftUI

struct TrashView: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if store.trashedNotes.isEmpty && store.trashedTabs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.trashedNotes) { trashedNote in
                            TrashNoteRow(trashedNote: trashedNote)
                        }
                        ForEach(store.trashedTabs) { trashedTab in
                            TrashTabRow(trashedTab: trashedTab)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18)
        .frame(width: 460, height: 420)
        .navigationTitle(L("휴지통"))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash.fill")
                .font(.system(size: 18, weight: .semibold))

            Text(L("휴지통"))
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text("\(store.trashedNotes.count + store.trashedTabs.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.black.opacity(0.72), in: Capsule())

            Spacer()

            Button {
                store.emptyTrash()
            } label: {
                Label(L("비우기"), systemImage: "flame")
            }
            .disabled(store.trashedNotes.isEmpty && store.trashedTabs.isEmpty)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(.secondary)

            Text(L("휴지통이 비어 있어요"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TrashNoteRow: View {
    @EnvironmentObject private var store: PosteightStore
    let trashedNote: TrashedStickyNote

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trashedNote.note.stickerSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: trashedNote.note.penHex))
                .frame(width: 32, height: 32)
                .background(Color(hex: trashedNote.note.paperHex), in: Rectangle())
                .overlay {
                    Rectangle()
                        .stroke(.black.opacity(0.08), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(trashedNote.note.selectedTab?.title ?? L("메모"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(Lf("탭 %ld개 · 할 일 %ld개", trashedNote.note.tabs.count, trashedNote.note.allItems.count))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.restoreNote(trashedNote.id)
            } label: {
                Label(L("복구"), systemImage: "arrow.uturn.backward")
            }

            Button {
                store.permanentlyDeleteNote(trashedNote.id)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("완전 삭제"))
        }
        .padding(10)
        .background(.quaternary.opacity(0.28), in: Rectangle())
        .overlay {
            Rectangle()
                .stroke(.black.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct TrashTabRow: View {
    @EnvironmentObject private var store: PosteightStore
    let trashedTab: TrashedMemoTab

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trashedTab.stickerSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: trashedTab.penHex))
                .frame(width: 32, height: 32)
                .background(Color(hex: trashedTab.paperHex), in: Rectangle())
                .overlay {
                    Rectangle()
                        .stroke(.black.opacity(0.08), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(trashedTab.tab.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(Lf("탭 · 할 일 %ld개", trashedTab.tab.items.count))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.restoreTab(trashedTab.id)
            } label: {
                Label(L("복구"), systemImage: "arrow.uturn.backward")
            }

            Button {
                store.permanentlyDeleteTab(trashedTab.id)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("완전 삭제"))
        }
        .padding(10)
        .background(.quaternary.opacity(0.28), in: Rectangle())
        .overlay {
            Rectangle()
                .stroke(.black.opacity(0.06), lineWidth: 1)
        }
    }
}
