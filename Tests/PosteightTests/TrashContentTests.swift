import Testing
@testable import Posteight

@Suite("Trash content")
struct TrashContentTests {
    @Test("Empty input rows do not count as tasks or appear in previews")
    func emptyRows() {
        let items = [TodoItem(title: ""), TodoItem(title: " \n\t"), TodoItem(title: "실제 할 일")]
        #expect(items.filter(\.hasTitle).map(\.title) == ["실제 할 일"])
        #expect(items.filter(\.hasContent).map(\.title) == ["실제 할 일"])
    }

    @Test("User-entered placeholder wording is still real content")
    func literalPlaceholder() {
        #expect(TodoItem(title: "할 일 입력").hasTitle)
        #expect(TodoItem(title: "New item").hasTitle)
    }

    @Test("Details remain visible after clearing a title but do not count as a task")
    func detailOnly() {
        let item = TodoItem(title: " ", detail: "남겨 둔 댓글")
        #expect(!item.hasTitle)
        #expect(item.hasContent)
        #expect(!TodoItem(title: "", detail: " \n").hasContent)
    }
}
