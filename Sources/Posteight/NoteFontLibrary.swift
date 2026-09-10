import AppKit
import CoreText
import SwiftUI
import UniformTypeIdentifiers

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
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard ["ttf", "otf"].contains(url.pathExtension.lowercased()),
                  let descriptor = Self.descriptor(at: url) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            entries.append(NoteFontEntry(id: url.deletingPathExtension().lastPathComponent,
                name: descriptor.name, postScriptName: descriptor.postScriptName, fileURL: url))
        }
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
        guard ["ttf", "otf"].contains(source.pathExtension.lowercased()),
              let descriptor = Self.descriptor(at: source) else { throw ImportError.invalidFont }
        guard !entries.contains(where: { $0.postScriptName == descriptor.postScriptName }) else {
            throw ImportError.duplicate
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let destination = directory.appendingPathComponent(id).appendingPathExtension(source.pathExtension.lowercased())
        try FileManager.default.copyItem(at: source, to: destination)
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(destination as CFURL, .process, &error)
        // A font already installed on the Mac can still be kept in the app's collection.
        guard registered || NSFont(name: descriptor.postScriptName, size: 13) != nil else {
            try? FileManager.default.removeItem(at: destination)
            throw ImportError.registration
        }
        entries.append(NoteFontEntry(id: id, name: descriptor.name,
            postScriptName: descriptor.postScriptName, fileURL: destination))
    }

    func remove(_ entry: NoteFontEntry) throws {
        guard let url = entry.fileURL else { return }
        try FileManager.default.removeItem(at: url)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        entries.removeAll { $0.id == entry.id }
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
