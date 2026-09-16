import Testing

// AppKit has one key window per process. Serializing each child suite alone still lets
// search and undo tests steal focus from each other while an async test yields.
@Suite(.serialized)
@MainActor
struct AppKitEditingTests {}

@MainActor
func waitForEditorState(_ condition: () -> Bool) async throws -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    repeat {
        // Give pending layout and delegate callbacks a turn, even if the value is already true.
        try await Task.sleep(for: .milliseconds(20))
        if condition() { return true }
    } while clock.now < deadline
    return false
}
