import Foundation
import UniformTypeIdentifiers

struct PortableHTMLDocument: Sendable {
    let html: String
    let embeddedResourceCount: Int
    let skippedResourceCount: Int
}

enum MarkdownExportResources {
    private static let maximumResourceBytes = 32 * 1_024 * 1_024
    private static let maximumTotalBytes = 96 * 1_024 * 1_024

    static func makePortable(_ html: String, baseURL: URL?) -> PortableHTMLDocument {
        guard let root = baseURL?.resolvingSymlinksInPath().standardizedFileURL,
              root.isFileURL,
              let regex = try? NSRegularExpression(pattern: #"(?i)\b(?:src|poster)\s*=\s*\"([^\"]+)\""#) else {
            return PortableHTMLDocument(html: html, embeddedResourceCount: 0, skippedResourceCount: 0)
        }

        let source = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: source.length))
        var result = html
        var embeddedCount = 0
        var skippedCount = 0
        var embeddedBytes = 0

        for match in matches.reversed() {
            let valueRange = match.range(at: 1)
            guard valueRange.location != NSNotFound else { continue }
            let escapedValue = source.substring(with: valueRange)
            let value = decodeHTMLEntities(escapedValue)
            guard let fileURL = localFileURL(for: value, root: root) else { continue }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard resourceValues.isRegularFile == true else {
                    skippedCount += 1
                    continue
                }
                if let size = resourceValues.fileSize,
                   size > maximumResourceBytes || embeddedBytes + size > maximumTotalBytes {
                    skippedCount += 1
                    continue
                }
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                guard data.count <= maximumResourceBytes,
                      embeddedBytes + data.count <= maximumTotalBytes else {
                    skippedCount += 1
                    continue
                }
                let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
                guard let range = Range(valueRange, in: result) else { continue }
                result.replaceSubrange(range, with: dataURL)
                embeddedCount += 1
                embeddedBytes += data.count
            } catch {
                skippedCount += 1
            }
        }

        return PortableHTMLDocument(html: result,
                                    embeddedResourceCount: embeddedCount,
                                    skippedResourceCount: skippedCount)
    }

    private static func localFileURL(for value: String, root: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix("//"),
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed.lowercased().hasPrefix("data:"),
              let parsed = URLComponents(string: trimmed),
              parsed.scheme == nil,
              parsed.host == nil else { return nil }

        let encodedPath = parsed.percentEncodedPath
        let relativePath = encodedPath.removingPercentEncoding ?? parsed.path
        guard !relativePath.isEmpty else { return nil }
        let target = root.appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let rootPath = root.path
        let targetPath = target.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else { return nil }
        return target
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
