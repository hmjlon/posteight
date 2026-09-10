import AppKit
import Foundation
import Testing
@testable import Posteight

@Suite("Note fonts", .serialized)
@MainActor
struct NoteFontTests {
    @Test func selectionPersistsAndSupportsUndoWithoutChangingLayout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let id = store.addNote()
        let original = try #require(store.notes.first { $0.id == id })
        store.clearEditingHistory()
        store.updateFont(id, fontID: "hana")
        #expect(store.undo())
        #expect(store.notes.first { $0.id == id }?.fontID == nil)
        #expect(store.redo())
        store.flush()
        let loaded = PosteightStore(directory: directory)
        let note = try #require(loaded.notes.first { $0.id == id })
        #expect(note.fontID == "hana")
        #expect(note.tabs == original.tabs)
        #expect(note.size == original.size)
        #expect(note.position == original.position)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        legacy.removeValue(forKey: "fontID")
        let decoded = try JSONDecoder().decode(StickyNote.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.fontID == nil)
    }

    @Test func fontSizePersistsAndUndoRestoresInheritance() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PosteightStore(directory: directory)
        let id = store.addNote()
        let original = try #require(store.notes.first { $0.id == id })
        #expect(original.fontSize == nil)
        store.clearEditingHistory()
        store.updateFontSize(id, size: .large)
        #expect(store.undo())
        #expect(store.notes.first { $0.id == id }?.fontSize == nil)
        #expect(store.redo())
        store.flush()
        let loaded = PosteightStore(directory: directory)
        let note = try #require(loaded.notes.first { $0.id == id })
        #expect(note.fontSize == .large)
        #expect(note.size == original.size)
        #expect(note.position == original.position)
        #expect(note.tabs == original.tabs)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        legacy.removeValue(forKey: "fontSize")
        let decoded = try JSONDecoder().decode(StickyNote.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.fontSize == nil)
        loaded.updateFontSize(id, size: nil)
        loaded.flush()
        #expect(PosteightStore(directory: directory).notes.first { $0.id == id }?.fontSize == nil)
        #expect(NoteFontSize.medium.adjustment == 0)
    }

    @Test func bundledFontAndFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fonts = NoteFontLibrary(directory: directory)
        let hana = try #require(fonts.fontName(for: "hana", defaultID: "system"))
        #expect(NSFont(name: hana, size: 15) != nil)
        #expect(fonts.fontName(for: nil, defaultID: "hana") == hana)
        #expect(fonts.fontName(for: "missing", defaultID: "hana") == hana)
        #expect(fonts.fontName(for: "system", defaultID: "hana") == nil)
        #expect(fonts.fontName(for: nil, defaultID: "missing") == nil)
    }

    @Test func customFontCopyReloadRemovalAndInvalidFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.ttf")
        try FileManager.default.copyItem(at: #require(NoteFontLibrary.bundledFontURL), to: source)
        let fontsDirectory = directory.appendingPathComponent("Fonts")
        let fonts = NoteFontLibrary(directory: fontsDirectory, bundledURL: nil)
        try fonts.add(source)
        #expect(throws: NoteFontLibrary.ImportError.duplicate) { try fonts.add(source) }
        let entry = try #require(fonts.entries.first { $0.fileURL != nil })
        try FileManager.default.removeItem(at: source)
        #expect(FileManager.default.fileExists(atPath: try #require(entry.fileURL).path))
        let reloaded = NoteFontLibrary(directory: fontsDirectory, bundledURL: nil)
        #expect(reloaded.entries.contains { $0.id == entry.id && $0.postScriptName == entry.postScriptName })
        try reloaded.remove(entry)
        #expect(reloaded.fontName(for: entry.id, defaultID: "system") == nil)
        #expect(!FileManager.default.fileExists(atPath: try #require(entry.fileURL).path))
        let invalid = directory.appendingPathComponent("invalid.ttf")
        try Data("not a font".utf8).write(to: invalid)
        #expect(throws: NoteFontLibrary.ImportError.invalidFont) { try reloaded.add(invalid) }
        #expect(reloaded.entries.count == 1)
    }
}
