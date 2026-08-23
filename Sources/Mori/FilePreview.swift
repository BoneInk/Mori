import Quartz
import SwiftUI

struct ExternalFilePreview: View {
    @EnvironmentObject private var document: DocumentStore
    let url: URL

    private var detail: String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let size = values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "Unknown size"
        let type = values?.contentType?.localizedDescription ?? (url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased())
        return "\(type) · \(size)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { document.closeFilePreview() } label: {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.borderless).help("Back to document")

                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 17)).foregroundStyle(document.theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show in Finder") { document.revealInFinder(url) }
                    .buttonStyle(.borderless)
                Button("Open in Default App") { document.openInDefaultApp(url) }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14).frame(height: 48)

            Divider().opacity(0.5)
            QuickLookPreview(url: url)
        }
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
        view?.autostarts = true
        view?.previewItem = url as NSURL
        return view!
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
        view.refreshPreviewItem()
    }
}
