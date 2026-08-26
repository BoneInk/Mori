import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var document: DocumentStore
    @State private var isDropTarget = false
    @State private var scrollSync = ScrollSyncState()

    var body: some View {
        ZStack {
            document.theme.background.ignoresSafeArea()

            HSplitView {
                if document.showSidebar && document.showFileLibrary && !document.focusMode {
                    SidebarView()
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 420)
                }
                if document.showSidebar && document.showOutline && document.previewFileURL == nil && document.isMarkdownDocument && !document.focusMode {
                    OutlinePane(scrollSync: scrollSync)
                        .frame(minWidth: 180, idealWidth: 215, maxWidth: 440)
                }

                VStack(spacing: 0) {
                    TopBar()
                    DocumentTabBar()
                    if let conflict = document.externalConflict {
                        ExternalConflictBanner(conflict: conflict)
                    }
                    Divider().opacity(0.45)

                    if let previewURL = document.previewFileURL {
                        ExternalFilePreview(url: previewURL)
                            .id(document.activeTabID)
                    } else {
                        WritingWorkspace(scrollSync: scrollSync)
                            .id(document.activeTabID)
                    }

                    StatusBar()
                }
                .frame(minWidth: 560)
                .layoutPriority(1)
            }

            if isDropTarget {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(document.theme.accent, style: StrokeStyle(lineWidth: 3, dash: [9, 7]))
                    .background(document.theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    .padding(24)
                    .allowsHitTesting(false)
            }

            if let notice = document.notice {
                VStack {
                    Spacer()
                    Text(notice)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThickMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
                        .padding(.bottom, 42)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: notice)
            }
        }
        .preferredColorScheme(document.theme.isDark ? .dark : .light)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.isFileURL else { return }
                Task { @MainActor in document.openFile(url) }
            }
            return true
        }
        .onOpenURL { url in
            document.openFile(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            document.persistForApplicationTermination()
        }
        .onDisappear {
            document.persistForApplicationTermination()
        }
        .sheet(isPresented: $document.showQuickOpen) {
            QuickOpenView()
                .environmentObject(document)
        }
        .sheet(isPresented: $document.showWorkspaceSearch) {
            WorkspaceSearchView()
                .environmentObject(document)
        }
        .sheet(isPresented: $document.showCommandPalette) {
            CommandPaletteView()
                .environmentObject(document)
        }
        .sheet(isPresented: $document.showDocumentHistory) {
            DocumentHistoryView()
                .environmentObject(document)
        }
        .sheet(isPresented: $document.showTableBuilder) {
            MarkdownTableBuilderView()
                .environmentObject(document)
        }
    }
}

private struct ExternalConflictBanner: View {
    @EnvironmentObject private var document: DocumentStore
    let conflict: ExternalFileConflict

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("File changed outside Mori").font(.system(size: 11.5, weight: .semibold))
                Text(conflict.url.lastPathComponent + " has a newer version on disk. Choose which version to keep.")
                    .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Reload Disk Version") { document.reloadExternalVersion() }
            Button("Save Mori Copy…") { document.saveConflictAs() }
            Button("Overwrite Disk…") { document.overwriteExternalVersion() }
                .foregroundStyle(.red)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12).frame(height: 46)
        .background(Color.orange.opacity(document.theme.isDark ? 0.12 : 0.08))
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }
}

private struct DocumentTabBar: View {
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(document.openTabs) { tab in
                        HStack(spacing: 6) {
                            Button { document.selectTab(tab.id) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: tab.isPreview ? "eye" : "doc.text")
                                        .font(.system(size: 9.5))
                                    Text(tab.title).lineLimit(1)
                                    if tab.id == document.activeTabID ? document.isDirty : tab.isDirty {
                                        Circle().fill(document.theme.accent).frame(width: 5, height: 5)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button { document.closeTab(tab.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 8.5, weight: .semibold))
                            }
                            .buttonStyle(.plain).opacity(tab.id == document.activeTabID ? 0.8 : 0.35)
                        }
                        .font(.system(size: 10.5, weight: tab.id == document.activeTabID ? .medium : .regular))
                        .padding(.leading, 10).padding(.trailing, 7).frame(height: 33)
                        .overlay(alignment: .bottom) {
                            if tab.id == document.activeTabID {
                                Rectangle().fill(document.theme.accent).frame(height: 2).padding(.horizontal, 7)
                            }
                        }
                        .contextMenu {
                            Button("Close") { document.closeTab(tab.id) }
                            if let path = tab.filePath ?? tab.previewPath {
                                Button("Show in Finder") { document.revealInFinder(URL(fileURLWithPath: path)) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 5)
            }
            Divider().frame(height: 17)
            Button { document.newDocument() } label: {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain).help("New tab").padding(.horizontal, 11)
        }
        .frame(height: 34)
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.026 : 0.016))
    }
}

private struct WritingWorkspace: View {
    @EnvironmentObject private var document: DocumentStore
    @ObservedObject var scrollSync: ScrollSyncState

    var body: some View {
        HSplitView {
            if !document.readerMode {
                MarkdownEditor(text: $document.text,
                               selection: $document.selectedRange,
                               command: $document.editorCommand,
                               scrollPosition: $scrollSync.position,
                               scrollSource: $scrollSync.source,
                               theme: document.theme,
                               typography: document.typography,
                               settings: document.editorSettings,
                               isMarkdown: document.isMarkdownDocument,
                               language: document.editorLanguage,
                               onInsertImages: document.insertImageFiles,
                               onPasteImage: document.insertPastedImage)
                    .frame(minWidth: 360)
            }

            if document.isMarkdownDocument && (document.readerMode || (document.showPreview && !document.focusMode)) {
                MarkdownPreview(markdown: document.text,
                                revision: document.textRevision,
                                title: document.title,
                                theme: document.theme,
                                typography: document.typography,
                                baseURL: document.fileURL?.deletingLastPathComponent(),
                                onOpenLocalFile: document.openFile,
                                scrollPosition: $scrollSync.position,
                                scrollSource: $scrollSync.source)
                    .frame(minWidth: 320)
            }
        }
    }
}

private struct TopBar: View {
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button { document.showFileLibrary.toggle(); document.showSidebar = true } label: {
                    Label("File Library", systemImage: document.showFileLibrary ? "checkmark.square.fill" : "square")
                }
                Button { document.showOutline.toggle(); document.showSidebar = true } label: {
                    Label("Document Outline", systemImage: document.showOutline ? "checkmark.square.fill" : "square")
                }
                Divider()
                Button("Toggle All Navigation") { document.toggleNavigation() }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Navigation panels")
            .accessibilityLabel("Navigation panels")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(document.title).font(.system(size: 13, weight: .semibold))
                    if document.isDirty { Circle().fill(document.theme.accent).frame(width: 5, height: 5) }
                }
                Text(document.displayURL?.deletingLastPathComponent().path(percentEncoded: false) ?? "Not yet saved")
                    .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            WorkspaceModeControl()

            Button { document.showQuickOpen = true } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Quick open (⌘P)")
            .accessibilityLabel("Quick open")

            Button { document.showCommandPalette = true } label: {
                Image(systemName: "command")
            }
            .help("Command palette (⇧⌘P)")
            .accessibilityLabel("Command palette")

            MoreActionsMenu()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.018 : 0.008))
    }
}

private struct WorkspaceModeControl: View {
    @EnvironmentObject private var document: DocumentStore

    private var isEditing: Bool { !document.readerMode && !document.showPreview }
    private var isSplit: Bool { !document.readerMode && document.showPreview }

    var body: some View {
        HStack(spacing: 1) {
            modeButton("Edit", systemImage: "pencil", isActive: isEditing) {
                if document.readerMode { document.toggleReaderMode() }
                document.focusMode = false
                document.showPreview = false
            }
            modeButton("Split", systemImage: "rectangle.split.2x1", isActive: isSplit) {
                if document.readerMode { document.toggleReaderMode() }
                document.focusMode = false
                document.showPreview = true
            }
            modeButton("Read", systemImage: "book.pages", isActive: document.readerMode) {
                if !document.readerMode { document.toggleReaderMode() }
            }
        }
        .padding(2)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
        .disabled(document.previewFileURL != nil || !document.isMarkdownDocument)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace mode")
    }

    private func modeButton(_ title: String,
                            systemImage: String,
                            isActive: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(isActive ? document.theme.accent : .secondary)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(isActive ? document.theme.background : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " mode")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct MoreActionsMenu: View {
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        Menu {
            Button("Save", systemImage: "square.and.arrow.down") { document.save() }
                .disabled(document.previewFileURL != nil)
            Button("Find in Document", systemImage: "text.magnifyingglass") { document.showFind() }
                .disabled(document.previewFileURL != nil || document.readerMode)
            Button("Document History", systemImage: "clock.arrow.circlepath") { document.showDocumentHistory = true }
                .disabled(document.fileURL == nil || document.previewFileURL != nil)
            Divider()
            Menu("Theme") {
                Picker("Theme", selection: $document.theme) {
                    ForEach(document.availableThemes) { theme in Text(theme.name).tag(theme) }
                }
            }
            SettingsLink { Label("Typography and Appearance", systemImage: "textformat.size") }
            Divider()
            MarkdownFormattingMenu()
            Button(document.focusMode ? "Exit Focus Mode" : "Focus Mode",
                   systemImage: document.focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                document.focusMode.toggle()
            }
            .disabled(document.previewFileURL != nil)
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions")
    }
}

private struct MarkdownFormattingMenu: View {
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        Menu("Formatting", systemImage: "textformat") {
            Button("Bold") { document.wrapSelection(left: "**", right: "**", placeholder: "bold text") }
            Button("Italic") { document.wrapSelection(left: "_", right: "_", placeholder: "italic text") }
            Button("Strikethrough") { document.wrapSelection(left: "~~", right: "~~", placeholder: "struck text") }
            Button("Link") { document.wrapSelection(left: "[", right: "](https://)", placeholder: "link text") }
            Button("Image…") { document.chooseImagesToInsert() }
            Button("Inline Code") { document.wrapSelection(left: "`", right: "`", placeholder: "code") }
            Divider()
            Button("Heading") { document.insert(prefix: "## ") }
            Button("Bulleted List") { document.insert(prefix: "- ") }
            Button("Numbered List") { document.insert(prefix: "1. ") }
            Button("Block Quote") { document.insert(prefix: "> ") }
            Button("Table…") { document.showTableBuilder = true }
            Divider()
            Button("Inline Math") { document.wrapSelection(left: "$", right: "$", placeholder: "E = mc^2") }
            Button("Display Math") { document.wrapSelection(left: "$$\n", right: "\n$$", placeholder: "\\int_0^1 x^2\\,dx") }
            Button("Fenced Code Block") { document.wrapSelection(left: "```text\n", right: "\n```", placeholder: "code") }
        }
        .disabled(document.previewFileURL != nil || !document.isMarkdownDocument || document.readerMode)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var document: DocumentStore
    @State private var workspaceSelection = Set<String>()
    @State private var workspaceQuery = ""

    private var filteredWorkspaceTree: [WorkspaceNode] {
        let query = workspaceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return document.displayedWorkspaceTree }
        return document.displayedWorkspaceTree.compactMap { filter($0, query: query) }
    }

    private var selectedWorkspaceURLs: [URL] {
        workspaceSelection
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private var pasteDestination: URL? {
        guard let root = document.workspaceURL else { return nil }
        let selected = selectedWorkspaceURLs
        guard selected.count == 1, let url = selected.first else {
            if let parent = selected.first?.deletingLastPathComponent(),
               selected.allSatisfy({ $0.deletingLastPathComponent() == parent }) {
                return parent
            }
            return root
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            ? url
            : url.deletingLastPathComponent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(document.theme.accent)
                    Image(systemName: "leaf.fill").foregroundStyle(.white).font(.system(size: 10.5))
                }.frame(width: 24, height: 24)
                Text("Mori").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { document.showFileLibrary = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless).help("Close file library")
            }
            .padding(.horizontal, 14).frame(height: 48)

            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WORKSPACE")
                        .font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
                    Text(document.workspaceURL?.lastPathComponent ?? "No folder open")
                        .font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { document.newDocument() } label: { Image(systemName: "doc.badge.plus") }
                    .help("New document")
                Button { document.openDocument() } label: { Image(systemName: "folder") }
                    .help("Open file")
                Button { document.chooseWorkspaceFolder() } label: { Image(systemName: "folder.badge.plus") }
                    .help(document.workspaceURL == nil ? "Open folder" : "Change folder")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider().opacity(0.45) }

            List(selection: $workspaceSelection) {
                Group {
                    HStack {
                        Text("FILES")
                            .font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                        Spacer()
                        if document.isLoadingWorkspace {
                            ProgressView().controlSize(.mini)
                        } else if document.workspaceURL != nil {
                            Button { document.showWorkspaceSearch = true } label: {
                                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 9.5))
                            }
                            .buttonStyle(.borderless).help("Search text in folder")
                            Button { document.refreshWorkspace() } label: {
                                Image(systemName: "arrow.clockwise").font(.system(size: 9.5))
                            }
                            .buttonStyle(.borderless).help("Refresh folder")
                            Button { document.closeWorkspaceFolder() } label: {
                                Image(systemName: "xmark.circle").font(.system(size: 9.5))
                            }
                            .buttonStyle(.borderless).help("Close folder")
                        }
                    }
                    .padding(.horizontal, 10).padding(.top, 9).padding(.bottom, 5)

                    if let root = document.workspaceURL {
                        HStack(spacing: 6) {
                            Image(systemName: "folder").foregroundStyle(document.theme.accent)
                            Text(root.lastPathComponent).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text(document.showMarkdownOnly ? "\(document.markdownFileCount)/\(document.workspaceFiles.count)" : "\(document.workspaceFiles.count)")
                                .font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary)
                            Menu {
                                Button { document.createMarkdownFile(in: root) } label: {
                                    Label("New Markdown File", systemImage: "doc.badge.plus")
                                }
                                Button { document.createFolder(in: root) } label: {
                                    Label("New Folder", systemImage: "folder.badge.plus")
                                }
                            } label: {
                                Image(systemName: "plus.circle").font(.system(size: 10))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Create an item in \(root.lastPathComponent)")
                            Button { document.showMarkdownOnly.toggle() } label: {
                                Image(systemName: document.showMarkdownOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                            .help(document.showMarkdownOnly ? "Show all files" : "Show Markdown files only")
                        }
                        .padding(.horizontal, 10).padding(.bottom, 3)
                        .onDrop(of: WorkspaceTransfer.dropTypes, isTargeted: nil) { providers in
                            acceptDrop(providers, into: root)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Filter files", text: $workspaceQuery)
                                .textFieldStyle(.plain)
                            if !workspaceQuery.isEmpty {
                                Button { workspaceQuery = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                        .padding(.horizontal, 8).padding(.vertical, 4)

                        OutlineGroup(filteredWorkspaceTree, children: \.children) { node in
                            WorkspaceNodeRow(
                                node: node,
                                root: root,
                                draggedURLs: workspaceSelection.contains(node.id) ? selectedWorkspaceURLs : [node.url],
                                onDrop: { providers in acceptDrop(providers, into: node.url) }
                            )
                            .tag(node.id)
                        }
                    } else {
                        Text("Open a folder to browse all of its files.")
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 10).padding(.bottom, 8)
                    }

                    Divider().opacity(0.35).padding(.horizontal, 7).padding(.vertical, 10)

                    HStack {
                        Text("RECENT")
                            .font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                        Spacer()
                        if !document.recentFiles.isEmpty {
                            Button { document.clearRecentFiles() } label: {
                                Image(systemName: "trash").font(.system(size: 9))
                            }
                            .buttonStyle(.borderless).help("Clear recent files")
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 4)

                    if document.recentFiles.isEmpty {
                        Text("Files you open will appear here.")
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                    } else {
                        ForEach(document.recentFiles, id: \.path) { url in
                            RecentFileRow(url: url)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 6)
            .onCopyCommand { selectedWorkspaceURLs.map { WorkspaceTransfer.provider(for: $0, cut: false) } }
            .onCutCommand { selectedWorkspaceURLs.map { WorkspaceTransfer.provider(for: $0, cut: true) } }
            .onPasteCommand(of: WorkspaceTransfer.pasteTypes) { providers in
                guard let destination = pasteDestination else { return }
                let move = providers.contains { $0.hasItemConformingToTypeIdentifier(WorkspaceTransfer.cutType) }
                WorkspaceTransfer.loadURLs(from: providers) { urls in
                    document.pasteWorkspaceItems(urls, into: destination, move: move)
                    workspaceSelection.removeAll()
                }
            }

            HStack(spacing: 8) {
                Text("\(document.workspaceFiles.count) files")
                Spacer()
                Text(document.showMarkdownOnly ? "Markdown only" : "All files")
            }
            .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.tertiary)
            .padding(.horizontal, 13).frame(height: 28)
            .overlay(alignment: .top) { Divider().opacity(0.45) }
        }
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.028 : 0.018))
    }

    private func acceptDrop(_ providers: [NSItemProvider], into directory: URL) -> Bool {
        WorkspaceTransfer.loadURLs(from: providers) { urls in
            document.handleDroppedWorkspaceItems(urls, into: directory)
            workspaceSelection.removeAll()
        }
        return true
    }

    private func filter(_ node: WorkspaceNode, query: String) -> WorkspaceNode? {
        if node.isDirectory {
            let children = (node.children ?? []).compactMap { filter($0, query: query) }
            if node.url.lastPathComponent.localizedCaseInsensitiveContains(query) {
                return node
            }
            return children.isEmpty ? nil : WorkspaceNode(url: node.url, isDirectory: true, children: children)
        }
        let relativePath: String
        if let root = document.workspaceURL, node.url.path.hasPrefix(root.path) {
            relativePath = String(node.url.path.dropFirst(root.path.count))
        } else {
            relativePath = node.url.lastPathComponent
        }
        return relativePath.localizedCaseInsensitiveContains(query) ? node : nil
    }
}

private struct OutlinePane: View {
    @EnvironmentObject private var document: DocumentStore
    let scrollSync: ScrollSyncState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("OUTLINE")
                    .font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text("\(document.headings.count)")
                    .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.tertiary)
                Button { document.showOutline = false } label: {
                    Image(systemName: "xmark").font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.borderless).help("Close document outline")
            }
            .padding(.horizontal, 14).frame(height: 45)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                Text("Article structure")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.bottom, 12)

            Divider().opacity(0.4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if document.headings.isEmpty {
                        VStack(spacing: 9) {
                            Image(systemName: "text.badge.plus").font(.system(size: 18)).foregroundStyle(.tertiary)
                            Text("Add headings to build\nyour article structure.")
                                .multilineTextAlignment(.center)
                                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 35)
                    }

                    ForEach(document.headings) { heading in
                        Button {
                            scrollSync.source = .outline
                            scrollSync.position = ScrollPosition(line: heading.line, fraction: 0)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(heading.level == 1 ? document.theme.accent : Color.secondary.opacity(0.35))
                                    .frame(width: heading.level == 1 ? 3 : 2,
                                           height: heading.level == 1 ? 15 : 10)
                                Text(heading.title)
                                    .font(.system(size: heading.level == 1 ? 11.5 : 10.8,
                                                  weight: heading.level <= 2 ? .medium : .regular))
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.leading, CGFloat(min(heading.level - 1, 4)) * 13)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Level \(heading.level) · line \(heading.line + 1)")
                    }
                }
                .padding(.horizontal, 5).padding(.vertical, 7)
            }
        }
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.018 : 0.008))
    }
}

private struct RecentFileRow: View {
    @EnvironmentObject private var document: DocumentStore
    let url: URL

    var body: some View {
        Button { document.openFile(url) } label: {
            HStack(spacing: 9) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12)).foregroundStyle(document.theme.accent)
                    .frame(width: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Text(url.deletingLastPathComponent().lastPathComponent)
                        .font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 9).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { document.openFile(url) }
            Button("Show in Finder") { document.revealInFinder(url) }
            Divider()
            Button("Remove from Recent") { document.removeRecent(url) }
        }
        .help(url.path(percentEncoded: false))
    }
}

private struct WorkspaceNodeRow: View {
    @EnvironmentObject private var document: DocumentStore
    let node: WorkspaceNode
    let root: URL
    let draggedURLs: [URL]
    let onDrop: ([NSItemProvider]) -> Bool

    var body: some View {
        if node.isDirectory {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(document.theme.accent.opacity(0.85))
                    .frame(width: 16)
                Text(node.url.lastPathComponent)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let children = node.children {
                    Text("\(children.count)")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8).padding(.vertical, 5)
            .help("Expand or collapse \(node.url.lastPathComponent)")
            .onDrag { WorkspaceTransfer.dragProvider(for: draggedURLs) }
            .onDrop(of: WorkspaceTransfer.dropTypes, isTargeted: nil, perform: onDrop)
            .contextMenu {
                Button("New Markdown File") { document.createMarkdownFile(in: node.url) }
                Button("New Folder") { document.createFolder(in: node.url) }
                Divider()
                Button("Rename…") { document.renameWorkspaceItem(node.url) }
                Button("Show in Finder") { document.revealInFinder(node.url) }
                Divider()
                Button("Move to Trash", role: .destructive) { document.moveWorkspaceItemToTrash(node.url) }
            }
        } else {
            WorkspaceFileRow(url: node.url, root: root, showParent: false, draggedURLs: draggedURLs)
        }
    }
}

private struct WorkspaceFileRow: View {
    @EnvironmentObject private var document: DocumentStore
    let url: URL
    let root: URL
    var showParent = true
    var draggedURLs: [URL]

    private var relativeParent: String {
        let parent = url.deletingLastPathComponent().path
        guard parent != root.path else { return root.lastPathComponent }
        return String(parent.dropFirst(min(parent.count, root.path.count + 1)))
    }

    private var icon: String {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return "doc.richtext"
        case "txt": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        case "pdf": return "doc.fill"
        case "swift", "js", "ts", "java", "py", "json", "yaml", "yml": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11)).foregroundStyle(document.isSupportedDocument(url) ? document.theme.accent : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 10.5, weight: document.isSupportedDocument(url) ? .medium : .regular))
                    .lineLimit(1)
                if showParent {
                    Text(relativeParent)
                        .font(.system(size: 8.5)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle()).padding(.horizontal, 8).padding(.vertical, 4)
        .onTapGesture(count: 2) { document.openWorkspaceFile(url) }
        .onDrag { WorkspaceTransfer.dragProvider(for: draggedURLs) }
        .contextMenu {
            Button(document.isSupportedDocument(url) ? "Open in Mori" : "Preview in Mori") {
                document.openWorkspaceFile(url)
            }
            if !document.isSupportedDocument(url) {
                Button("Open in Default App") { document.openInDefaultApp(url) }
            }
            Button("Show in Finder") { document.revealInFinder(url) }
            Divider()
            Button("Rename…") { document.renameWorkspaceItem(url) }
            Button("Move to Trash", role: .destructive) { document.moveWorkspaceItemToTrash(url) }
        }
        .help(url.path(percentEncoded: false))
    }
}

private enum WorkspaceTransfer {
    static let cutType = "com.local.mori.workspace-cut"
    private static let selectionType = "com.local.mori.workspace-selection"
    static let dropTypes = [UTType.fileURL.identifier, selectionType]
    static let pasteTypes: [UTType] = [.fileURL]

    static func provider(for url: URL, cut: Bool) -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        if cut {
            provider.registerDataRepresentation(forTypeIdentifier: cutType, visibility: .all) { completion in
                completion(Data([1]), nil)
                return nil
            }
        }
        return provider
    }

    static func dragProvider(for urls: [URL]) -> NSItemProvider {
        let normalized = urls.map(\.standardizedFileURL)
        guard normalized.count > 1,
              let data = try? JSONEncoder().encode(normalized.map(\.path)) else {
            return provider(for: normalized.first ?? URL(fileURLWithPath: "/"), cut: false)
        }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: selectionType, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        guard !providers.isEmpty else { completion([]); return }
        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [URL] = []

        func append(_ urls: [URL]) {
            lock.lock()
            collected.append(contentsOf: urls)
            lock.unlock()
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(selectionType) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: selectionType) { data, _ in
                    defer { group.leave() }
                    guard let data,
                          let paths = try? JSONDecoder().decode([String].self, from: data) else { return }
                    append(paths.map { URL(fileURLWithPath: $0).standardizedFileURL })
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        append([url.standardizedFileURL])
                    } else if let url = item as? NSURL {
                        append([(url as URL).standardizedFileURL])
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        append([url.standardizedFileURL])
                    } else if let value = item as? String,
                              let url = URL(string: value), url.isFileURL {
                        append([url.standardizedFileURL])
                    }
                }
            }
        }

        group.notify(queue: .main) {
            var seen = Set<String>()
            completion(collected.filter { seen.insert($0.path).inserted })
        }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        HStack(spacing: 15) {
            Label(document.isDirty ? "Edited" : "Saved", systemImage: document.isDirty ? "circle.fill" : "checkmark.circle")
                .labelStyle(.titleAndIcon)
            Spacer()
            if let url = document.previewFileURL {
                Text(url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased())
                Text(document.isImageFile(url) ? "Mori image preview" : "System preview")
            } else {
                Text(document.readerMode ? "Reader" : document.documentFormat.label)
                Menu {
                    ForEach(document.encodingChoices) { choice in
                        Button {
                            document.selectEncoding(choice.rawValue)
                        } label: {
                            if choice.name == document.encodingLabel {
                                Label(choice.name, systemImage: "checkmark")
                            } else {
                                Text(choice.name)
                            }
                        }
                    }
                } label: {
                    Text(document.encodingLabel)
                }
                .menuStyle(.borderlessButton).fixedSize().help("Text encoding")
                Menu {
                    Picker("Line Endings", selection: $document.lineEnding) {
                        ForEach(DocumentLineEnding.allCases) { ending in
                            Text(ending.rawValue).tag(ending)
                        }
                    }
                } label: {
                    Text(document.lineEnding.rawValue)
                }
                .menuStyle(.borderlessButton).fixedSize().help("Line endings")
                if let selection = document.selectionStats {
                    Text("\(selection.characters) selected")
                }
                Text("\(document.stats.characters) characters")
                Text("\(document.stats.words) words")
            }
        }
        .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).frame(height: 28)
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.018 : 0.008))
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }
}

private struct QuickOpenView: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [URL] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = document.quickOpenFiles
        guard !value.isEmpty else { return Array(files.prefix(100)) }
        let terms = value.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return files.lazy.filter { url in
            let candidate = url.path.lowercased()
            return terms.allSatisfy(candidate.contains)
        }.prefix(200).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(document.theme.accent)
                TextField("Type a file name or path", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($searchFocused)
                    .onSubmit { if let first = matches.first { open(first) } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(16)

            Divider()

            if matches.isEmpty {
                ContentUnavailableView("No Matching Files", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(matches, id: \.path) { url in
                    Button { open(url) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: quickOpenIcon(url))
                                .foregroundStyle(document.theme.accent).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                    .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle()).padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider()
            HStack {
                Text("↩ Open")
                Text("⌘P Quick Open")
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .frame(width: 620, height: 430)
        .background(document.theme.background)
        .preferredColorScheme(document.theme.isDark ? .dark : .light)
        .onAppear { searchFocused = true }
    }

    private func open(_ url: URL) {
        dismiss()
        DispatchQueue.main.async { document.openFile(url) }
    }

    private func quickOpenIcon(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        case "swift", "js", "ts", "java", "py", "go", "rs", "json", "yaml", "yml": return "chevron.left.forwardslash.chevron.right"
        case "pdf": return "doc.fill"
        default: return "doc.text"
        }
    }
}

private struct WorkspaceSearchView: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var caseSensitive = false
    @State private var regularExpression = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(document.theme.accent)
                TextField("Search text in every file", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($searchFocused)
                Toggle("Aa", isOn: $caseSensitive)
                    .toggleStyle(.button)
                    .help("Match case")
                Toggle(".*", isOn: $regularExpression)
                    .toggleStyle(.button)
                    .help("Use regular expression")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(16)

            Divider()

            Group {
                if document.workspaceURL == nil {
                    ContentUnavailableView {
                        Label("No Folder Open", systemImage: "folder")
                    } description: {
                        Text("Open a folder before searching its contents.")
                    } actions: {
                        Button("Open Folder…") { document.chooseWorkspaceFolder() }
                    }
                } else if let error = document.workspaceSearchError {
                    ContentUnavailableView("Invalid Search", systemImage: "exclamationmark.magnifyingglass",
                                           description: Text(error))
                } else if document.isSearchingWorkspace {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Searching folder…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Search Folder", systemImage: "text.magnifyingglass",
                                           description: Text("Find text across editable files in the open folder."))
                } else if document.workspaceSearchResults.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "doc.text.magnifyingglass")
                } else {
                    List(document.workspaceSearchResults) { result in
                        Button { open(result) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(document.theme.accent)
                                    Text(result.url.lastPathComponent)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("· \(result.line + 1):\(result.column + 1)")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(relativePath(for: result.url))
                                        .font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                                }
                                Text(result.preview.isEmpty ? " " : result.preview)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                if !document.workspaceSearchResults.isEmpty {
                    Text(document.workspaceSearchResults.count >= 1_000
                         ? "Showing first 1,000 matches"
                         : "\(document.workspaceSearchResults.count) matches")
                } else {
                    Text("⇧⌘F Search in Folder")
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .frame(width: 720, height: 520)
        .background(document.theme.background)
        .preferredColorScheme(document.theme.isDark ? .dark : .light)
        .onAppear {
            searchFocused = true
            document.searchWorkspace(query, caseSensitive: caseSensitive, regularExpression: regularExpression)
        }
        .onChange(of: query) { _, _ in runSearch() }
        .onChange(of: caseSensitive) { _, _ in runSearch() }
        .onChange(of: regularExpression) { _, _ in runSearch() }
    }

    private func runSearch() {
        document.searchWorkspace(query, caseSensitive: caseSensitive, regularExpression: regularExpression)
    }

    private func open(_ result: WorkspaceSearchResult) {
        dismiss()
        DispatchQueue.main.async { document.openWorkspaceSearchResult(result) }
    }

    private func relativePath(for url: URL) -> String {
        guard let root = document.workspaceURL else { return url.deletingLastPathComponent().path }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(rootPath) ? String(url.path.dropFirst(rootPath.count)) : url.path
    }
}
