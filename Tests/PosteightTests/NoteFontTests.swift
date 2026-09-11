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
        defer { try? FileManager.default.removeItem(at: directory) }
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

    /// A library holding exactly one imported font, plus the paths to its folder and manifest.
    private func imported() throws -> (root: URL, fonts: URL, manifest: URL, entry: NoteFontEntry) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.ttf")
        try FileManager.default.copyItem(at: #require(NoteFontLibrary.bundledFontURL), to: source)

        let fontsDirectory = root.appendingPathComponent("Fonts")
        let library = NoteFontLibrary(directory: fontsDirectory, bundledURL: nil)
        try library.add(source)
        let entry = try #require(library.entries.first { $0.fileURL != nil })
        return (root, fontsDirectory, fontsDirectory.appendingPathComponent("manifest.json"), entry)
    }

    /// The folder is outside any sandbox container, so anything running as this user can drop a
    /// file into it. Registering it would hand CoreText's parser an attacker's bytes on every
    /// launch, for as long as the file sits there.
    @Test func unrecordedFontInTheFolderIsNotRegistered() throws {
        let (root, fonts, _, entry) = try imported()
        defer { try? FileManager.default.removeItem(at: root) }

        // A real, parseable font — it is refused for not being in the manifest, nothing else.
        let planted = fonts.appendingPathComponent("\(UUID().uuidString).ttf")
        try FileManager.default.copyItem(at: #require(NoteFontLibrary.bundledFontURL), to: planted)

        let reloaded = NoteFontLibrary(directory: fonts, bundledURL: nil)
        #expect(reloaded.entries.filter { $0.fileURL != nil }.map(\.id) == [entry.id])
        #expect(!reloaded.entries.contains { $0.fileURL == planted })
        // Refused, not deleted: the app does not own files it did not write.
        #expect(FileManager.default.fileExists(atPath: planted.path))
    }

    @Test func recordedFontWithChangedBytesIsNotRegistered() throws {
        let (root, fonts, _, entry) = try imported()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = try #require(entry.fileURL)
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: url, options: .atomic)

        let reloaded = NoteFontLibrary(directory: fonts, bundledURL: nil)
        #expect(!reloaded.entries.contains { $0.id == entry.id })
        #expect(reloaded.entries.filter { $0.fileURL != nil }.isEmpty)
    }

    /// A manifest that has been tampered with must not become a way to read files elsewhere.
    @Test func manifestFileNameCannotEscapeTheFolder() throws {
        let (root, fonts, _, _) = try imported()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NoteFontLibrary(directory: fonts, bundledURL: nil)

        // Outside the folder, reachable only by climbing out of it.
        let outside = root.appendingPathComponent("outside.ttf")
        try FileManager.default.copyItem(at: #require(NoteFontLibrary.bundledFontURL), to: outside)
        #expect(library.verifiedURL(fileName: "../outside.ttf") == nil)
        #expect(library.verifiedURL(fileName: "/etc/hosts") == nil)
        #expect(library.verifiedURL(fileName: "..") == nil)

        // A symlink sitting inside the folder is refused too: it is not a regular file.
        let link = fonts.appendingPathComponent("link.ttf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(library.verifiedURL(fileName: "link.ttf") == nil)
    }

    @Test func oversizedFileIsRefused() throws {
        let (root, fonts, _, _) = try imported()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NoteFontLibrary(directory: fonts, bundledURL: nil)

        // Sparse, so this costs no disk. Only its reported size matters.
        let huge = fonts.appendingPathComponent("huge.ttf")
        #expect(FileManager.default.createFile(atPath: huge.path, contents: nil))
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(NoteFontLibrary.maximumFontBytes + 1))
        try handle.close()

        #expect(library.verifiedURL(fileName: "huge.ttf") == nil)
        #expect(throws: NoteFontLibrary.ImportError.invalidFont) { try library.add(huge) }
    }

    /// A manifest entry claiming a built-in id would put a second `system` into `entries`, which
    /// `ForEach` takes as an `Identifiable` array.
    @Test func manifestCannotClaimABuiltInID() throws {
        let (root, fonts, manifest, entry) = try imported()
        defer { try? FileManager.default.removeItem(at: root) }

        var rows = try #require(JSONSerialization.jsonObject(
            with: try Data(contentsOf: manifest)) as? [[String: Any]])
        rows[0]["id"] = "system"
        try JSONSerialization.data(withJSONObject: rows).write(to: manifest, options: .atomic)

        let reloaded = NoteFontLibrary(directory: fonts, bundledURL: nil)
        #expect(reloaded.entries.filter { $0.id == "system" }.count == 1)
        #expect(reloaded.entries.first { $0.id == "system" }?.fileURL == nil)
        #expect(!reloaded.entries.contains { $0.id == entry.id })
    }

    /// Installs made before the manifest existed have fonts the user did import. Losing them on
    /// upgrade would read as the app throwing their fonts away.
    @Test func fontsImportedBeforeTheManifestSurviveTheUpgrade() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fonts = root.appendingPathComponent("Fonts")
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)

        // Exactly what the old importer left behind: <UUID>.ttf and no manifest.
        let legacy = fonts.appendingPathComponent("\(UUID().uuidString).ttf")
        try FileManager.default.copyItem(at: #require(NoteFontLibrary.bundledFontURL), to: legacy)
        // And one file it never wrote, which the scan must not adopt.
        let planted = fonts.appendingPathComponent("system.ttf")
        try FileManager.default.copyItem(at: #require(NoteFontLibrary.bundledFontURL), to: planted)

        let upgraded = NoteFontLibrary(directory: fonts, bundledURL: nil)
        let adopted = upgraded.entries.filter { $0.fileURL != nil }
        #expect(adopted.map(\.fileURL) == [legacy])
        // Migrated entries get a fresh UUID id rather than the file name they came from.
        #expect(UUID(uuidString: try #require(adopted.first).id) != nil)

        // The scan runs once. A font dropped in afterwards has no way back into the manifest.
        let later = fonts.appendingPathComponent("\(UUID().uuidString).ttf")
        try FileManager.default.copyItem(at: #require(NoteFontLibrary.bundledFontURL), to: later)
        let relaunched = NoteFontLibrary(directory: fonts, bundledURL: nil)
        #expect(relaunched.entries.filter { $0.fileURL != nil }.map(\.fileURL) == [legacy])
    }

    /// A fresh install writes a manifest even with nothing in it, so "no manifest" can only ever
    /// mean "never started" and the one-time scan cannot be re-armed by deleting fonts.
    @Test func afreshInstallRecordsAnEmptyManifest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fonts = root.appendingPathComponent("Fonts")

        _ = NoteFontLibrary(directory: fonts, bundledURL: nil)
        let manifest = fonts.appendingPathComponent("manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifest.path))

        let planted = fonts.appendingPathComponent("\(UUID().uuidString).ttf")
        try FileManager.default.copyItem(at: #require(NoteFontLibrary.bundledFontURL), to: planted)
        #expect(NoteFontLibrary(directory: fonts, bundledURL: nil).entries.allSatisfy { $0.fileURL == nil })
    }

    @Test func importedFontsAreStoredPrivateToTheUser() throws {
        let (root, fonts, manifest, entry) = try imported()
        defer { try? FileManager.default.removeItem(at: root) }

        func mode(_ url: URL) throws -> Int {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return try #require(attributes[.posixPermissions] as? NSNumber).intValue
        }
        #expect(try mode(fonts) == 0o700)
        #expect(try mode(manifest) == 0o600)
        #expect(try mode(#require(entry.fileURL)) == 0o600)
    }
}
