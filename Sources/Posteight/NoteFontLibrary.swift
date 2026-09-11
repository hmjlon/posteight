import AppKit
import CoreText
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

/// What the app wrote down when the user imported a font, and the only thing it will register
/// later. Without a record of its own, the app re-parses whatever happens to be in the folder.
private struct FontManifestEntry: Codable {
    /// Always a UUID, so it can never collide with a built-in entry id.
    let id: String
    /// A bare file name. Never a path.
    let fileName: String
    let sha256: String
    let postScriptName: String
    let displayName: String
}

struct NoteFontEntry: Identifiable {
    let id: String
    let name: String
    let postScriptName: String?
    var fileURL: URL? = nil

    func title(language: AppLanguage) -> String {
        switch id {
        case "system": L("기본체", language: language)
        case "hana": L("손글씨", language: language)
        default: name
        }
    }
}

/// Fonts are registered only in this process; the user's system font collection is untouched.
@MainActor
final class NoteFontLibrary: ObservableObject {
    static let shared = NoteFontLibrary()
    @Published private(set) var entries: [NoteFontEntry] = []
    let directory: URL

    static var bundledFontURL: URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: "HanaHandwriting", withExtension: "ttf")
            ?? bundle.url(forResource: "HanaHandwriting", withExtension: "ttf", subdirectory: "Resources")
    }

    init(directory: URL = PosteightStore.storeDirectory.appendingPathComponent("Fonts", isDirectory: true),
         bundledURL: URL? = NoteFontLibrary.bundledFontURL) {
        self.directory = directory
        entries = [NoteFontEntry(id: "system", name: "", postScriptName: nil)]
        if let url = bundledURL, let descriptor = Self.descriptor(at: url) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            entries.append(NoteFontEntry(id: "hana", name: "", postScriptName: descriptor.postScriptName))
        }
        loadImportedFonts()
    }

    // MARK: - Imported fonts

    /// Ids the built-in entries own. An imported font can never claim one.
    static let reservedIDs: Set<String> = ["system", "hana"]
    static let fontExtensions = ["ttf", "otf"]
    /// The bundled font is 6.3MB. Anything approaching this is not something a user picked.
    static let maximumFontBytes = 64 * 1024 * 1024
    private var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    private func loadManifest() -> [FontManifestEntry] {
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([FontManifestEntry].self, from: data)
        else { return [] }
        return entries
    }

    private func saveManifest(_ manifest: [FontManifestEntry]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
    }

    /// Streamed, so a font never has to sit in memory whole just to be identified.
    nonisolated static func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Resolves a bare file name inside the font folder and nowhere else. `../` cannot climb out
    /// and a symlink cannot point out, because `attributesOfItem` reports the link itself rather
    /// than following it, so anything but a regular file is refused here.
    func verifiedURL(fileName: String) -> URL? {
        guard !fileName.contains("/"), fileName != ".", fileName != ".." else { return nil }
        let url = directory.appendingPathComponent(fileName)
        guard url.deletingLastPathComponent().resolvingSymlinksInPath()
                == directory.resolvingSymlinksInPath() else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? .max <= Self.maximumFontBytes
        else { return nil }
        return url
    }

    /// The font folder sits outside any sandbox container and carries no TCC protection, so any
    /// process running as this user can drop a file into it. CoreText's font parser has a long
    /// history of memory-corruption CVEs, and handing it every file in that folder on every
    /// launch turns one write into a parser attack that repeats forever in this app's context.
    /// Only fonts this app recorded at import, still byte-for-byte what it recorded, are loaded.
    private func loadImportedFonts() {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            migrateToManifest()
            return
        }
        for entry in loadManifest() {
            guard let url = verified(entry) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            entries.append(NoteFontEntry(id: entry.id, name: entry.displayName,
                                         postScriptName: entry.postScriptName, fileURL: url))
        }
    }

    private func verified(_ entry: FontManifestEntry) -> URL? {
        guard !Self.reservedIDs.contains(entry.id),
              let url = verifiedURL(fileName: entry.fileName),
              let digest = try? Self.digest(of: url),
              digest == entry.sha256.lowercased(),
              let descriptor = Self.descriptor(at: url),
              descriptor.postScriptName == entry.postScriptName
        else {
            NSLog("Posteight: skipped unverified font \(entry.fileName)")
            return nil
        }
        return url
    }

    /// Runs once, on the first launch after this app learned to keep a manifest. Installs made
    /// before then have fonts the user did import, with no record to check them against, and
    /// dropping them silently would read as the app losing their fonts.
    ///
    /// The scan is deliberately narrow: only files named the way the old importer named them —
    /// `<UUID>.ttf` — are adopted. A manifest is written even when nothing is found, so this
    /// path never runs again and a file dropped in later has no way back into it.
    private func migrateToManifest() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        var manifest: [FontManifestEntry] = []

        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let fileName = url.lastPathComponent
            guard Self.fontExtensions.contains(url.pathExtension.lowercased()),
                  UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                  let url = verifiedURL(fileName: fileName),
                  let descriptor = Self.descriptor(at: url),
                  let digest = try? Self.digest(of: url) else { continue }

            // A fresh id rather than the file name. The old scheme took the id from the file
            // name, so a restored backup holding `system.ttf` produced a second entry with the
            // built-in's id and broke the picker.
            let entry = FontManifestEntry(id: UUID().uuidString, fileName: fileName,
                                          sha256: digest, postScriptName: descriptor.postScriptName,
                                          displayName: descriptor.name)
            manifest.append(entry)
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            entries.append(NoteFontEntry(id: entry.id, name: entry.displayName,
                                         postScriptName: entry.postScriptName, fileURL: url))
        }

        try? saveManifest(manifest)
    }

    func contains(_ id: String?) -> Bool {
        id == nil || entries.contains { $0.id == id }
    }

    func resolvedID(for id: String?, defaultID: String) -> String {
        if let id, entries.contains(where: { $0.id == id }) { return id }
        return entries.contains(where: { $0.id == defaultID }) ? defaultID : "system"
    }

    func fontName(for id: String?, defaultID: String) -> String? {
        entries.first { $0.id == resolvedID(for: id, defaultID: defaultID) }?.postScriptName
    }

    private static func descriptor(at url: URL) -> (name: String, postScriptName: String)? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        let font = CTFontCreateWithFontDescriptor(descriptor, 13, nil)
        return (CTFontCopyFullName(font) as String, CTFontCopyPostScriptName(font) as String)
    }

    enum ImportError: Error { case invalidFont, duplicate, registration }

    func add(_ source: URL) throws {
        guard Self.fontExtensions.contains(source.pathExtension.lowercased()) else {
            throw ImportError.invalidFont
        }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        guard size <= Self.maximumFontBytes else { throw ImportError.invalidFont }
        guard let descriptor = Self.descriptor(at: source) else { throw ImportError.invalidFont }
        guard !entries.contains(where: { $0.postScriptName == descriptor.postScriptName }) else {
            throw ImportError.duplicate
        }

        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let id = UUID().uuidString
        let fileName = id + "." + source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent(fileName)
        guard !manager.fileExists(atPath: destination.path) else { throw ImportError.invalidFont }

        // The bytes are written out rather than copied, so the stored font inherits none of the
        // source file's ACLs or extended attributes.
        try Data(contentsOf: source, options: [.mappedIfSafe]).write(to: destination, options: .atomic)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(destination as CFURL, .process, &error)
        // A font already installed on the Mac can still be kept in the app's collection.
        guard registered || NSFont(name: descriptor.postScriptName, size: 13) != nil else {
            try? manager.removeItem(at: destination)
            throw ImportError.registration
        }

        do {
            try saveManifest(loadManifest() + [FontManifestEntry(
                id: id, fileName: fileName, sha256: try Self.digest(of: destination),
                postScriptName: descriptor.postScriptName, displayName: descriptor.name)])
        } catch {
            // An unrecorded font would not come back on the next launch, so fail the import
            // outright rather than leave a file the app will refuse to load.
            CTFontManagerUnregisterFontsForURL(destination as CFURL, .process, nil)
            try? manager.removeItem(at: destination)
            throw error
        }

        entries.append(NoteFontEntry(id: id, name: descriptor.name,
            postScriptName: descriptor.postScriptName, fileURL: destination))
    }

    func remove(_ entry: NoteFontEntry) throws {
        guard let url = entry.fileURL else { return }
        try FileManager.default.removeItem(at: url)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        entries.removeAll { $0.id == entry.id }
        try saveManifest(loadManifest().filter { $0.id != entry.id })
    }
}

struct FontSettingsSection: View {
    @ObservedObject private var fonts = NoteFontLibrary.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var errorMessage: String?

    var body: some View {
        Section(L("폰트")) {
            Picker(L("기본 메모 폰트"), selection: Binding(
                get: { fonts.contains(settings.defaultFontID) ? settings.defaultFontID : "system" },
                set: { settings.defaultFontID = $0 }
            )) {
                ForEach(fonts.entries) { entry in
                    Text(entry.title(language: settings.language)).tag(entry.id)
                }
            }
            Picker(L("글자 크기"), selection: $settings.defaultFontSize) {
                ForEach(NoteFontSize.allCases) { size in
                    Text(size.title(in: settings.language)).tag(size)
                }
            }
            .pickerStyle(.segmented)
            Text(L("오늘 할 일을 적어보세요"))
                .font(fonts.fontName(for: nil, defaultID: settings.defaultFontID)
                    .map { .custom($0, size: 15 + settings.defaultFontSize.adjustment) }
                    ?? .system(size: 15 + settings.defaultFontSize.adjustment))
                .padding(.vertical, 4)
            Text(L("각 포스트잇의 필통에서 다른 폰트를 선택할 수 있어요."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(fonts.entries.filter { $0.fileURL != nil }) { entry in
                HStack {
                    Text(entry.name).lineLimit(1)
                    Spacer()
                    Button(L("삭제"), role: .destructive) {
                        do {
                            try fonts.remove(entry)
                            if settings.defaultFontID == entry.id { settings.defaultFontID = "system" }
                        } catch { errorMessage = L("폰트를 삭제하지 못했어요. 다시 시도해 주세요.") }
                    }
                }
            }
            FontImportButton()
            Text(L("TTF·OTF 파일을 보관합니다. 삭제하면 해당 메모는 기본 폰트로 돌아갑니다."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .alert(L("폰트"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L("확인")) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

}

/// The same file picker and validation are available in settings and each pencil case.
struct FontImportButton: View {
    @ObservedObject private var fonts = NoteFontLibrary.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var errorMessage: String?

    var body: some View {
        Button(L("내 폰트 추가…")) { importFont() }
            .alert(L("폰트"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(L("확인")) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }

    private func importFont() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ttf"), UTType(filenameExtension: "otf")].compactMap { $0 }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { try fonts.add(url) }
            catch NoteFontLibrary.ImportError.duplicate { errorMessage = L("이미 추가된 폰트입니다.") }
            catch { errorMessage = L("폰트를 추가하지 못했어요. 올바른 TTF·OTF 파일인지 확인해 주세요.") }
        }
    }
}
