import Foundation

enum MermaidRuntime {
    static let script: String? = {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            Bundle.main.url(forResource: "mermaid.tiny", withExtension: "js", subdirectory: "Mermaid"),
            sourceRoot.appendingPathComponent("Resources/Mermaid/mermaid.tiny.js")
        ].compactMap { $0 }

        for url in candidates {
            if let value = try? String(contentsOf: url, encoding: .utf8), !value.isEmpty {
                return value
            }
        }
        return nil
    }()
}
