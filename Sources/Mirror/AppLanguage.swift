import AppKit
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    var menuTitle: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    private static let preferenceKey = "MirrorAppLanguage"

    @Published var selection: AppLanguage {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: Self.preferenceKey) }
    }

    init() {
        LegacyBrandMigration.performIfNeeded()
        let stored = UserDefaults.standard.string(forKey: Self.preferenceKey)
        selection = stored.flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
    }

    var locale: Locale { selection.locale }

    func selectAndRelaunch(_ language: AppLanguage) {
        guard language != selection else { return }
        selection = language
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        let applicationURL = Bundle.main.bundleURL
        guard applicationURL.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func text(_ key: String) -> String {
        guard selection == .simplifiedChinese,
              let path = Bundle.main.path(forResource: selection.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
