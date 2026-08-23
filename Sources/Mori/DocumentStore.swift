import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    @Published var text: String = DocumentStore.welcomeText {
        didSet {
            guard text != oldValue else { return }
            textRevision &+= 1
            headings = Self.extractHeadings(from: text)
            guard !isLoading else { return }
            isDirty = true
            scheduleAutosave()
        }
    }
    @Published var fileURL: URL?
    @Published private(set) var textRevision = 0
    @Published var isDirty = false
    @Published var showSidebar = true
    @Published var showFileLibrary = true
    @Published var showOutline = true
    @Published var showPreview = true
    @Published var focusMode = false
    @Published var readerMode = false
    @Published var theme: EditorTheme = .paper
    @Published var selectedRange = NSRange(location: 0, length: 0)
    @Published var editorCommand: EditorCommand?
    @Published var notice: String?
    @Published private(set) var recentFiles: [URL]
    @Published private(set) var headings: [Heading] = DocumentStore.extractHeadings(from: DocumentStore.welcomeText)
    @Published private(set) var workspaceURL: URL?
    @Published private(set) var workspaceFiles: [URL] = []
    @Published private(set) var workspaceTree: [WorkspaceNode] = []
    @Published private(set) var markdownWorkspaceTree: [WorkspaceNode] = []
    @Published private(set) var markdownFileCount = 0
    @Published private(set) var isLoadingWorkspace = false
    @Published var showMarkdownOnly = false
    @Published private(set) var previewFileURL: URL?

    private var isLoading = false
    private var autosaveTask: Task<Void, Never>?

    init() {
        recentFiles = Self.loadRecentFiles()
        previewFileURL = nil
        if let path = UserDefaults.standard.string(forKey: "MoriWorkspaceFolder"),
           FileManager.default.fileExists(atPath: path) {
            workspaceURL = URL(fileURLWithPath: path).standardizedFileURL
        } else {
            workspaceURL = nil
        }
        if workspaceURL != nil { Task { refreshWorkspace() } }
    }

    var displayURL: URL? { previewFileURL ?? fileURL }
    var title: String { displayURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }
    var displayedWorkspaceTree: [WorkspaceNode] { showMarkdownOnly ? markdownWorkspaceTree : workspaceTree }
    private static func extractHeadings(from text: String) -> [Heading] {
        text.components(separatedBy: .newlines).enumerated().compactMap { index, line in
            let marks = line.prefix { $0 == "#" }
            guard !marks.isEmpty, marks.count <= 6, line.dropFirst(marks.count).first == " " else { return nil }
            return Heading(level: marks.count, title: line.dropFirst(marks.count + 1).trimmingCharacters(in: .whitespaces), line: index)
        }
    }
    var stats: WritingStats { WritingStats(text: text) }

    func newDocument() {
        guard confirmDiscardIfNeeded() else { return }
        isLoading = true
        text = "# Untitled\n\nStart writing…"
        fileURL = nil
        previewFileURL = nil
        isDirty = false
        isLoading = false
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFile(url)
    }

    func chooseWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        panel.message = "Choose a folder to show its files in Mori."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspaceURL = url.standardizedFileURL
        UserDefaults.standard.set(workspaceURL?.path, forKey: "MoriWorkspaceFolder")
        refreshWorkspace()
    }

    func refreshWorkspace() {
        guard let root = workspaceURL else { workspaceFiles = []; return }
        isLoadingWorkspace = true
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.enumerateWorkspace(in: root)
            }.value
            guard let self, self.workspaceURL == root else { return }
            self.workspaceFiles = snapshot.files
            self.workspaceTree = snapshot.tree
            self.markdownWorkspaceTree = snapshot.markdownTree
            self.markdownFileCount = snapshot.markdownCount
            self.isLoadingWorkspace = false
        }
    }

    func closeWorkspaceFolder() {
        workspaceURL = nil
        workspaceFiles = []
        workspaceTree = []
        markdownWorkspaceTree = []
        markdownFileCount = 0
        UserDefaults.standard.removeObject(forKey: "MoriWorkspaceFolder")
    }

    func openWorkspaceFile(_ url: URL) {
        openFile(url)
    }

    func isSupportedDocument(_ url: URL) -> Bool {
        ["md", "markdown", "txt"].contains(url.pathExtension.lowercased())
    }

    func openFile(_ url: URL) {
        isSupportedDocument(url) ? open(url: url) : previewFile(url)
    }

    func previewFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        previewFileURL = url.standardizedFileURL
        recordRecent(url)
        flash("Previewing \(url.lastPathComponent)")
    }

    func closeFilePreview() {
        previewFileURL = nil
    }

    func openInDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func toggleNavigation() {
        if !showSidebar || (!showFileLibrary && !showOutline) {
            showSidebar = true
            showFileLibrary = true
            showOutline = true
        } else {
            showSidebar.toggle()
        }
    }

    func open(url: URL) {
        guard confirmDiscardIfNeeded() else { return }
        do {
            let value = try String(contentsOf: url, encoding: .utf8)
            isLoading = true
            text = value
            fileURL = url
            previewFileURL = nil
            isDirty = false
            isLoading = false
            recordRecent(url)
            flash("Opened \(url.lastPathComponent)")
        } catch {
            showError("Couldn’t open the document", error)
        }
    }

    func save() {
        guard let fileURL else { saveAs(); return }
        write(to: fileURL)
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(title).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        write(to: url)
    }

    func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "\(title).html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let html = MarkdownRenderer.document(markdown: text, title: title, theme: theme)
            try html.write(to: url, atomically: true, encoding: .utf8)
            flash("Exported \(url.lastPathComponent)")
        } catch {
            showError("Couldn’t export HTML", error)
        }
    }

    func insert(prefix: String) {
        editorCommand = .insert(prefix)
    }

    func wrapSelection(left: String, right: String, placeholder: String) {
        editorCommand = .wrap(left: left, right: right, placeholder: placeholder)
    }

    func jump(to heading: Heading) {
        let lines = text.components(separatedBy: .newlines)
        let location = lines.prefix(heading.line).reduce(0) { $0 + ($1 as NSString).length + 1 }
        editorCommand = .select(NSRange(location: location, length: (lines[heading.line] as NSString).length))
    }

    func toggleReaderMode() {
        readerMode.toggle()
        if readerMode { focusMode = false }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func removeRecent(_ url: URL) {
        recentFiles.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        persistRecentFiles()
    }

    func clearRecentFiles() {
        recentFiles.removeAll()
        persistRecentFiles()
    }

    private func write(to url: URL) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            recordRecent(url)
            flash("Saved")
        } catch {
            showError("Couldn’t save the document", error)
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard let url = fileURL else { return }
        let snapshot = text
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            do {
                try snapshot.write(to: url, atomically: true, encoding: .utf8)
                self?.isDirty = false
            } catch { }
        }
    }

    private func confirmDiscardIfNeeded() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(title)?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: save(); return !isDirty
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func flash(_ message: String) {
        notice = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            if self?.notice == message { self?.notice = nil }
        }
    }

    private func showError(_ message: String, _ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.runModal()
    }

    private func recordRecent(_ url: URL) {
        let normalized = url.standardizedFileURL
        recentFiles.removeAll { $0.standardizedFileURL == normalized }
        recentFiles.insert(normalized, at: 0)
        if recentFiles.count > 10 { recentFiles.removeLast(recentFiles.count - 10) }
        persistRecentFiles()
    }

    private func persistRecentFiles() {
        UserDefaults.standard.set(recentFiles.map(\.path), forKey: "MoriRecentFiles")
    }

    private static func loadRecentFiles() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: "MoriRecentFiles") ?? []
        return paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private nonisolated static func enumerateWorkspace(in root: URL) -> WorkspaceSnapshot {
        var allFiles: [URL] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey]

        func nodes(in directory: URL) -> [WorkspaceNode] {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { return [] }

            return contents.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: keys), values.isHidden != true else { return nil }
                if values.isDirectory == true && values.isPackage != true && values.isSymbolicLink != true {
                    let children = nodes(in: url)
                    return WorkspaceNode(url: url, isDirectory: true, children: children.isEmpty ? nil : children)
                }
                guard values.isRegularFile == true || values.isPackage == true else { return nil }
                allFiles.append(url)
                return WorkspaceNode(url: url, isDirectory: false, children: nil)
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
        }

        func markdownNode(_ node: WorkspaceNode) -> WorkspaceNode? {
            if !node.isDirectory {
                return ["md", "markdown"].contains(node.url.pathExtension.lowercased()) ? node : nil
            }
            let children = (node.children ?? []).compactMap(markdownNode)
            guard !children.isEmpty else { return nil }
            return WorkspaceNode(url: node.url, isDirectory: true, children: children)
        }

        let tree = nodes(in: root)
        let markdownTree = tree.compactMap(markdownNode)
        let markdownCount = allFiles.lazy.filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) }.count
        return WorkspaceSnapshot(files: allFiles, tree: tree, markdownTree: markdownTree, markdownCount: markdownCount)
    }

    static let welcomeText = """
    # Welcome to Mori

    A quiet place for clear thinking.

    ## Write naturally

    Mori keeps Markdown close, while the live canvas shows the shape of your document as you type. Try **bold**, _emphasis_, `inline code`, or a [link](https://example.com).

    > Good writing begins with a little room to breathe.

    ## Keep your flow

    - [x] Open or drop a Markdown file
    - [x] Navigate from the outline
    - [ ] Turn the next thought into words

    ```swift
    let idea = "small, focused, useful"
    print(idea)
    ```

    ---

    Use **⌘S** to save, **⇧⌘F** for focus mode, and **⌥⌘2** to toggle the preview.
    """
}

enum EditorCommand: Equatable {
    case insert(String)
    case wrap(left: String, right: String, placeholder: String)
    case select(NSRange)
}
