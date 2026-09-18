import Foundation

struct NoteSearchResult: Identifiable, Equatable {
    struct ID: Hashable {
        let noteID: UUID
        let tabID: UUID
    }

    var id: ID { ID(noteID: noteID, tabID: tab.id) }
    let noteID: UUID
    let tab: MemoTab
    let matchingItems: [TodoItem]
    let matchesHeading: Bool
}

/// Searches only live notes supplied by the caller; visibility and tab selection do not limit it.
enum NoteSearch {
    static func query(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func ranges(in text: String, query: String) -> [Range<String.Index>] {
        let term = self.query(query)
        guard !term.isEmpty else { return [] }
        var matches: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: term, options: .caseInsensitive,
                                     range: start..<text.endIndex) {
            matches.append(range)
            start = range.upperBound
        }
        return matches
    }

    static func results(in notes: [StickyNote], query: String) -> [NoteSearchResult] {
        let term = self.query(query)
        guard !term.isEmpty else { return [] }
        func matches(_ text: String) -> Bool {
            text.range(of: term, options: .caseInsensitive) != nil
        }
        var results: [NoteSearchResult] = []
        for note in notes {
            for tab in note.tabs {
                let heading = matches(tab.name) || matches(tab.title)
                let items = tab.items.filter { matches($0.title) || matches($0.detail ?? "") }
                if heading || !items.isEmpty {
                    results.append(NoteSearchResult(noteID: note.id, tab: tab,
                                                    matchingItems: items, matchesHeading: heading))
                }
            }
        }
        // Keep the existing note/tab order within each relevance group.
        return results.filter(\.matchesHeading) + results.filter { !$0.matchesHeading }
    }
}

/// A transient navigation request. Offsets use UTF-16, as required by AppKit editors.
struct SearchFocusRequest: Equatable {
    enum Target: Hashable {
        case tabName
        case tabTitle
        case itemTitle(UUID)
        case itemDetail(UUID)

        var itemID: UUID? {
            switch self {
            case .itemTitle(let id), .itemDetail(let id): id
            default: nil
            }
        }
    }

    let id = UUID()
    let noteID: UUID
    let tabID: UUID
    let target: Target
    let query: String

    func caret(in text: String) -> NSRange? {
        guard let match = NoteSearch.ranges(in: text, query: query).first else { return nil }
        return NSRange(location: NSRange(match, in: text).upperBound, length: 0)
    }
}

struct NoteSearchHit: Identifiable {
    struct ID: Hashable {
        let resultID: NoteSearchResult.ID
        let target: SearchFocusRequest.Target
    }
    let id: ID
    let text: String
    let isDone: Bool
}

extension NoteSearchResult {
    func hits(query: String) -> [NoteSearchHit] {
        var hits: [NoteSearchHit] = []
        func append(_ text: String, _ target: SearchFocusRequest.Target, done: Bool = false) {
            guard !NoteSearch.ranges(in: text, query: query).isEmpty else { return }
            hits.append(NoteSearchHit(id: .init(resultID: id, target: target), text: text, isDone: done))
        }
        append(tab.name, .tabName)
        append(tab.title, .tabTitle)
        for item in matchingItems {
            append(item.title, .itemTitle(item.id), done: item.isDone)
            append(item.detail ?? "", .itemDetail(item.id), done: item.isDone)
        }
        return hits
    }
}
