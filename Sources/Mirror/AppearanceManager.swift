import AppKit
import CoreText
import Foundation
import UniformTypeIdentifiers

enum AppearanceManager {
    private static let preferencesKey = "MirrorAppearancePreferencesV1"
    private static let customThemesKey = "MirrorCustomThemesV1"

    struct Preferences: Codable {
        var selectedThemeID: String
        var typography: TypographySettings
        var editor: EditorBehaviorSettings?
    }

    static func load() -> (theme: EditorTheme, typography: TypographySettings, editor: EditorBehaviorSettings, customThemes: [EditorTheme]) {
        registerImportedFonts()
        let decoder = JSONDecoder()
        let defaults = UserDefaults.standard
        let custom = defaults.data(forKey: customThemesKey)
            .flatMap { try? decoder.decode([EditorTheme].self, from: $0) } ?? []
        let preferences = defaults.data(forKey: preferencesKey)
            .flatMap { try? decoder.decode(Preferences.self, from: $0) }
        let themes = EditorTheme.builtIns + custom
        let theme = themes.first { $0.id == preferences?.selectedThemeID } ?? .paper
        return (theme, preferences?.typography ?? .standard, preferences?.editor ?? .standard, custom)
    }

    static func save(theme: EditorTheme,
                     typography: TypographySettings,
                     editor: EditorBehaviorSettings,
                     customThemes: [EditorTheme]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Preferences(selectedThemeID: theme.id, typography: typography, editor: editor)) {
            UserDefaults.standard.set(data, forKey: preferencesKey)
        }
        if let data = try? encoder.encode(customThemes) {
            UserDefaults.standard.set(data, forKey: customThemesKey)
        }
    }

    static var fontFamilies: [String] {
        (CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static var importedFontURLs: [URL] {
        guard let folder = try? fontsFolder(create: false) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { ["otf", "ttf", "ttc"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []
    }

    static func importFonts() throws -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Import Fonts"
        panel.prompt = "Import"
        panel.message = "Imported fonts are copied into Mirror and are only registered for Mirror."
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["otf", "ttf", "ttc"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return [] }
        let folder = try fontsFolder(create: true)
        var imported: [URL] = []
        for source in panel.urls {
            let destination = uniqueDestination(for: source, in: folder)
            try FileManager.default.copyItem(at: source, to: destination)
            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(destination as CFURL, .process, &error) else {
                try? FileManager.default.removeItem(at: destination)
                throw (error?.takeRetainedValue() as Error?) ?? CocoaError(.fileReadUnknown)
            }
            imported.append(destination)
        }
        return imported
    }

    static func removeImportedFont(_ url: URL, completion: @escaping (Error?) -> Void) {
        var registrationError: Unmanaged<CFError>?
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &registrationError)
        NSWorkspace.shared.recycle([url]) { _, error in completion(error) }
    }

    static func registerImportedFonts() {
        for url in importedFontURLs {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    private static func fontsFolder(create: Bool) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: create)
        let folder = support.appendingPathComponent("Mirror/Fonts", isDirectory: true)
        if create { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        return folder
    }

    private static func uniqueDestination(for source: URL, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent(source.lastPathComponent)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent) \(index).\(source.pathExtension)")
            index += 1
        }
        return candidate
    }
}
