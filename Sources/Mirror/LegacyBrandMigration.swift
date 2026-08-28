import Foundation

/// Carries local state forward from installations created before the app and
/// package were renamed. New values always win, so the migration is safe to
/// run more than once and never overwrites data already written by Mirror.
enum LegacyBrandMigration {
    private static let currentBrand = "Mirror"
    private static let legacyBrand = ["Mo", "ri"].joined()

    private static let migration: Void = {
        migrateDefaults()
        migrateApplicationSupport()
    }()

    static func performIfNeeded() {
        _ = migration
    }

    private static func migrateDefaults() {
        let legacyIdentifier = "com.local.\(legacyBrand.lowercased())"
        guard let legacyDomain = UserDefaults.standard.persistentDomain(forName: legacyIdentifier) else { return }

        let defaults = UserDefaults.standard
        for (key, value) in legacyDomain {
            let migratedKey = key
                .replacingOccurrences(of: legacyBrand, with: currentBrand)
                .replacingOccurrences(of: legacyBrand.lowercased(), with: currentBrand.lowercased())
            // Mirror intentionally defaults to Simplified Chinese. Do not let
            // a stale language override from the previous bundle silently put
            // a newly renamed installation back into English.
            guard migratedKey != "\(currentBrand)AppLanguage",
                  migratedKey != "AppleLanguages" else { continue }
            guard defaults.object(forKey: migratedKey) == nil else { continue }
            defaults.set(value, forKey: migratedKey)
        }
    }

    private static func migrateApplicationSupport() {
        let manager = FileManager.default
        guard let support = try? manager.url(for: .applicationSupportDirectory,
                                             in: .userDomainMask,
                                             appropriateFor: nil,
                                             create: true) else { return }
        let source = support.appendingPathComponent(legacyBrand, isDirectory: true)
        let destination = support.appendingPathComponent(currentBrand, isDirectory: true)
        guard manager.fileExists(atPath: source.path) else { return }

        if !manager.fileExists(atPath: destination.path) {
            try? manager.copyItem(at: source, to: destination)
            return
        }
        try? mergeMissingContents(from: source, into: destination, using: manager)
    }

    private static func mergeMissingContents(from source: URL,
                                             into destination: URL,
                                             using manager: FileManager) throws {
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try manager.contentsOfDirectory(at: source,
                                                    includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles]) {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let target = destination.appendingPathComponent(item.lastPathComponent,
                                                            isDirectory: isDirectory)
            if !manager.fileExists(atPath: target.path) {
                try manager.copyItem(at: item, to: target)
            } else if isDirectory {
                try mergeMissingContents(from: item, into: target, using: manager)
            }
        }
    }
}
