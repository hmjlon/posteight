import AppKit
import SwiftUI

struct NoteSearchView: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: NoteSearchHit.ID?
    @FocusState private var isSearchFocused: Bool

    private var results: [NoteSearchResult] {
        NoteSearch.results(in: store.notes, query: query)
    }

    var body: some View {
        let matches = results
        let hits = matches.flatMap { $0.hits(query: query) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("모든 메모에서 검색"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit { openSelected(hits) }
                    .onKeyPress(.downArrow) { moveSelection(1, in: hits); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(-1, in: hits); return .handled }
                if !query.isEmpty {
                    Button {
                        query = ""
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(L("검색어 지우기"))
                    .accessibilityLabel(L("검색어 지우기"))
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            if NoteSearch.query(query).isEmpty {
                message(L("찾고 싶은 단어를 입력하세요"),
                        detail: L("모든 탭의 이름, 제목, 할 일과 세부사항을 검색해요"))
            } else if matches.isEmpty {
                message(L("검색 결과가 없어요"), detail: L("다른 단어로 검색해 보세요"))
            } else {
                Text(Lf("탭 %ld개에서 찾았어요", matches.count))
                    .font(.caption).foregroundStyle(.secondary)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(matches) { result in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(result.tab.name).font(.headline)
                                        .padding(.horizontal, 12)
                                    ForEach(result.hits(query: query)) { hit in
                                        Button { open(hit) } label: {
                                            HStack(alignment: .top, spacing: 7) {
                                                Image(systemName: symbol(for: hit))
                                                    .foregroundStyle(.secondary)
                                                highlighted(hit.text)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .padding(12)
                                            .background(selection == hit.id
                                                ? Color.accentColor.opacity(0.12) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .id(hit.id)
                                    }
                                }

                            }
                        }
                    }
                    .onChange(of: selection) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 420, minHeight: 360)
        .navigationTitle(L("메모 검색"))
        .onAppear { isSearchFocused = true }
        .onChange(of: query) { _, _ in selection = results.flatMap { $0.hits(query: query) }.first?.id }
        .onChange(of: hits.map(\.id)) { _, ids in
            if selection == nil || !ids.contains(selection!) { selection = ids.first }
        }
        .onExitCommand { dismiss() }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func symbol(for hit: NoteSearchHit) -> String {
        switch hit.id.target {
        case .tabName: "rectangle.on.rectangle"
        case .tabTitle: "textformat"
        case .itemTitle: hit.isDone ? "checkmark.circle.fill" : "circle"
        case .itemDetail: "text.bubble"
        }
    }

    private func highlighted(_ text: String) -> Text {
        var value = AttributedString(text)
        for range in NoteSearch.ranges(in: text, query: query) {
            if let range = Range(range, in: value) {
                value[range].backgroundColor = Color.yellow.opacity(0.35)
                value[range].font = .body.bold()
            }
        }
        return Text(value)
    }

    private func moveSelection(_ offset: Int, in matches: [NoteSearchHit]) {
        guard !matches.isEmpty else { return }
        let current = matches.firstIndex { $0.id == selection } ?? (offset > 0 ? -1 : matches.count)
        selection = matches[min(max(current + offset, 0), matches.count - 1)].id
    }

    private func openSelected(_ matches: [NoteSearchHit]) {
        if let result = matches.first(where: { $0.id == selection }) ?? matches.first { open(result) }
    }

    private func open(_ hit: NoteSearchHit) {
        let destination = hit.id.resultID
        guard !AppLock.shared.isLocked,
              let tab = store.notes.first(where: { $0.id == destination.noteID })?
                .tabs.first(where: { $0.id == destination.tabID }),
              hit.id.target.itemID.map({ id in tab.items.contains { $0.id == id } }) ?? true
        else { return }
        store.presentedDetailItemID = nil
        store.selectTab(noteID: destination.noteID, tabID: destination.tabID)
        store.searchFocusRequest = SearchFocusRequest(
            noteID: destination.noteID, tabID: destination.tabID,
            target: hit.id.target, query: query
        )
        dismiss()
        NoteWindowCoordinator.shared.present(destination.noteID) { openWindow(value: $0) }
        NSApp.activate(ignoringOtherApps: true)
    }
}
