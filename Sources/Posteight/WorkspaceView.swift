import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var store: PosteightStore
    @Environment(\.openWindow) private var openWindow
    @State private var isShowingDailyLog = false
    @State private var isShowingTrash = false

    var body: some View {
        workspaceBar
            .padding(8)
            .sheet(isPresented: $isShowingDailyLog) {
                DailyLogPreviewView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $isShowingTrash) {
                TrashView()
                    .environmentObject(store)
            }
            .task {
                openAllNotes()
            }
            .onChange(of: store.notes.map(\.id)) { previousIDs, currentIDs in
                for noteID in currentIDs where !previousIDs.contains(noteID) {
                    openWindow(value: noteID)
                }
            }
    }

    private var workspaceBar: some View {
        HStack(spacing: 8) {
            Text("Posteight")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.74))

            Button {
                let noteID = store.addNote()
                openWindow(value: noteID)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .help("새 포스트잇")

            Button {
                openAllNotes()
            } label: {
                Image(systemName: "square.stack.3d.up")
                    .frame(width: 22, height: 22)
            }
            .help("모든 포스트잇 보기")

            Button {
                isShowingDailyLog = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 22, height: 22)
            }
            .help("오늘 기록 미리보기")

            Button {
                isShowingTrash = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: store.trashedNotes.isEmpty ? "trash" : "trash.fill")
                        .frame(width: 22, height: 22)

                    if !store.trashedNotes.isEmpty {
                        Text("\(store.trashedNotes.count)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 13, height: 13)
                            .background(Color.black.opacity(0.72), in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
            }
            .help("휴지통")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }

    private func openAllNotes() {
        for note in store.notes {
            openWindow(value: note.id)
        }
    }
}
