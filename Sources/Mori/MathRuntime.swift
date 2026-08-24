import Foundation

enum MathRuntime {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func resourceURL(name: String, extension fileExtension: String, subdirectory: String? = "KaTeX") -> URL? {
        let bundled = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
        let source = sourceRoot
            .appendingPathComponent("Resources/KaTeX", isDirectory: true)
            .appendingPathComponent(subdirectory == "KaTeX/fonts" ? "fonts" : "", isDirectory: true)
            .appendingPathComponent("\(name).\(fileExtension)")
        return [bundled, source].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static let script: String? = {
        guard let url = resourceURL(name: "katex.min", extension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    static let style: String? = {
        guard let cssURL = resourceURL(name: "katex.min", extension: "css"),
              var css = try? String(contentsOf: cssURL, encoding: .utf8) else { return nil }
        let fontFolderCandidates = [
            Bundle.main.resourceURL?.appendingPathComponent("KaTeX/fonts", isDirectory: true),
            sourceRoot.appendingPathComponent("Resources/KaTeX/fonts", isDirectory: true)
        ].compactMap { $0 }
        guard let fontFolder = fontFolderCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let fonts = try? FileManager.default.contentsOfDirectory(at: fontFolder, includingPropertiesForKeys: nil) else {
            return css
        }
        for font in fonts where font.pathExtension.lowercased() == "woff2" {
            guard let data = try? Data(contentsOf: font) else { continue }
            let token = "url(fonts/\(font.lastPathComponent))"
            css = css.replacingOccurrences(of: token,
                                           with: "url(data:font/woff2;base64,\(data.base64EncodedString()))")
        }
        css = css.replacingOccurrences(
            of: #",url\(fonts/[^\)]+\.(?:woff|ttf)\) format\(\"[^\"]+\"\)"#,
            with: "",
            options: .regularExpression
        )
        return css
    }()
}
