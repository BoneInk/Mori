import SwiftUI
import UniformTypeIdentifiers

private enum MoriMotion {
    static let fast = Animation.easeOut(duration: 0.14)
    static let control = Animation.easeInOut(duration: 0.2)
    static let panel = Animation.spring(response: 0.32, dampingFraction: 0.88)
}

private func withMoriAnimation(_ reduceMotion: Bool, _ updates: () -> Void) {
    if reduceMotion {
        updates()
    } else {
        withAnimation(MoriMotion.panel, updates)
    }
}

struct ContentView: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTarget = false
    @State private var scrollSync = ScrollSyncState()

    var body: some View {
        ZStack {
            document.theme.background.ignoresSafeArea()

            HSplitView {
                if document.showSidebar && document.showFileLibrary && !document.focusMode {
                    SidebarView()
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 420)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                if document.showSidebar && document.showOutline && document.previewFileURL == nil && document.isMarkdownDocument && !document.focusMode {
                    OutlinePane(scrollSync: scrollSync)
                        .frame(minWidth: 180, idealWidth: 215, maxWidth: 440)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    TopBar()
                    DocumentTabBar()
                    if let conflict = document.externalConflict {
                        ExternalConflictBanner(conflict: conflict)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Divider().opacity(0.45)

                    if let previewURL = document.previewFileURL {
                        ExternalFilePreview(url: previewURL)
                            .id(document.activeTabID)
                            .transition(.opacity)
                    } else {
                        WritingWorkspace(scrollSync: scrollSync)
                            .id(document.activeTabID)
                            .transition(.opacity)
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
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
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
                .animation(reduceMotion ? nil : .spring(response: 0.35), value: notice)
            }
        }
        .animation(reduceMotion ? nil : MoriMotion.panel, value: document.showFileLibrary)
        .animation(reduceMotion ? nil : MoriMotion.panel, value: document.showOutline)
        .animation(reduceMotion ? nil : MoriMotion.panel, value: document.showSidebar)
        .animation(reduceMotion ? nil : MoriMotion.control, value: document.focusMode)
        .animation(reduceMotion ? nil : MoriMotion.fast, value: isDropTarget)
        .animation(reduceMotion ? nil : MoriMotion.control, value: document.externalConflict)
        .preferredColorScheme(document.theme.isDark ? .dark : .light)
        .ignoresSafeArea(.container, edges: .top)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(document.openTabs) { tab in
                        DocumentTabItem(tab: tab)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading)),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.horizontal, 5)
                .animation(reduceMotion ? nil : MoriMotion.control,
                           value: document.openTabs.map(\.id))
            }
            Divider().frame(height: 17)
            Button {
                withMoriAnimation(reduceMotion) { document.newDocument() }
            } label: {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain).help("New tab").padding(.horizontal, 11)
        }
        .frame(height: 34)
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.026 : 0.016))
    }
}

private struct DocumentTabItem: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tab: OpenDocumentTab
    @State private var isHovered = false

    private var isActive: Bool { tab.id == document.activeTabID }
    private var isDirty: Bool { isActive ? document.isDirty : tab.isDirty }

    var body: some View {
        HStack(spacing: 6) {
            Button { document.selectTab(tab.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: tab.isPreview ? "eye" : "doc.text")
                        .font(.system(size: 9.5))
                        .foregroundStyle(isActive ? document.theme.accent : .secondary)
                    Text(tab.title).lineLimit(1)
                    if isDirty {
                        Circle().fill(document.theme.accent).frame(width: 5, height: 5)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withMoriAnimation(reduceMotion) { document.closeTab(tab.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isActive || isHovered ? 0.75 : 0)
        }
        .font(.system(size: 10.5, weight: isActive ? .medium : .regular))
        .padding(.leading, 10).padding(.trailing, 7).frame(height: 33)
        .background {
            if isHovered && !isActive {
                RoundedRectangle(cornerRadius: 5)
                    .fill(document.theme.foreground.opacity(document.theme.isDark ? 0.07 : 0.045))
                    .padding(.vertical, 3)
            }
        }
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(document.theme.accent).frame(height: 2).padding(.horizontal, 7)
            }
        }
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(MoriMotion.fast) { isHovered = hovering }
            }
        }
        .animation(reduceMotion ? nil : MoriMotion.fast, value: isActive)
        .contextMenu {
            Button("Close") { document.closeTab(tab.id) }
            if let path = tab.filePath ?? tab.previewPath {
                Button("Show in Finder") { document.revealInFinder(URL(fileURLWithPath: path)) }
            }
        }
    }
}

private struct WritingWorkspace: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var scrollSync: ScrollSyncState

    var body: some View {
        HSplitView {
            if !document.readerMode {
                VStack(spacing: 0) {
                    WorkspacePaneHeader(
                        title: document.isMarkdownDocument ? "MARKDOWN" : document.documentFormat.label.uppercased(),
                        detail: "Source"
                    )
                    ZStack(alignment: .topLeading) {
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
                        if document.text.isEmpty {
                            Text(document.isMarkdownDocument ? "Start writing in Markdown…" : "Start writing…")
                                .font(.system(size: CGFloat(document.typography.editorFontSize)))
                                .foregroundStyle(document.theme.foreground.opacity(0.28))
                                .padding(.leading, 45).padding(.top, 35)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(minWidth: 360)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if document.isMarkdownDocument && (document.readerMode || (document.showPreview && !document.focusMode)) {
                VStack(spacing: 0) {
                    WorkspacePaneHeader(title: "PREVIEW", detail: document.readerMode ? "Reader" : "Live sync")
                    ZStack {
                        MarkdownPreview(markdown: document.text,
                                        revision: document.textRevision,
                                        title: document.title,
                                        theme: document.theme,
                                        typography: document.typography,
                                        baseURL: document.fileURL?.deletingLastPathComponent(),
                                        onOpenLocalFile: document.openFile,
                                        syncMode: document.editorSettings.scrollSyncMode,
                                        scrollPosition: $scrollSync.position,
                                        scrollSource: $scrollSync.source)
                        if document.text.isEmpty && document.readerMode {
                            ContentUnavailableView(
                                "Nothing to read yet",
                                systemImage: "doc.text",
                                description: Text("Switch to Edit and start writing.")
                            )
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                }
                .frame(minWidth: 320)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : MoriMotion.panel, value: document.readerMode)
        .animation(reduceMotion ? nil : MoriMotion.panel, value: document.showPreview)
        .animation(reduceMotion ? nil : MoriMotion.control, value: document.focusMode)
        .animation(reduceMotion ? nil : MoriMotion.fast, value: document.text.isEmpty)
    }
}

private struct WorkspacePaneHeader: View {
    @EnvironmentObject private var document: DocumentStore
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.45)
            Spacer()
            Text(detail)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.015 : 0.006))
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }
}

private struct TopBar: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasLeadingNavigationPane: Bool {
        guard document.showSidebar, !document.focusMode else { return false }
        if document.showFileLibrary { return true }
        return document.showOutline && document.previewFileURL == nil && document.isMarkdownDocument
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withMoriAnimation(reduceMotion) {
                    if !document.showSidebar {
                        document.showSidebar = true
                        document.showFileLibrary = true
                    } else {
                        document.showFileLibrary.toggle()
                    }
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(document.showSidebar && document.showFileLibrary ? document.theme.accent : .secondary)
                    .scaleEffect(document.showSidebar && document.showFileLibrary ? 1 : 0.93)
            }
            .help(document.showFileLibrary ? "Hide file library" : "Show file library")
            .accessibilityLabel("File library")
            .accessibilityAddTraits(document.showSidebar && document.showFileLibrary ? .isSelected : [])

            Button {
                withMoriAnimation(reduceMotion) {
                    if !document.showSidebar {
                        document.showSidebar = true
                        document.showOutline = true
                    } else {
                        document.showOutline.toggle()
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(document.showSidebar && document.showOutline ? document.theme.accent : .secondary)
                    .scaleEffect(document.showSidebar && document.showOutline ? 1 : 0.93)
            }
            .disabled(document.previewFileURL != nil || !document.isMarkdownDocument)
            .help(document.showOutline ? "Hide document outline" : "Show document outline")
            .accessibilityLabel("Document outline")
            .accessibilityAddTraits(document.showSidebar && document.showOutline ? .isSelected : [])

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(document.title).font(.system(size: 13, weight: .semibold))
                    if document.isDirty { Circle().fill(document.theme.accent).frame(width: 5, height: 5) }
                }
                Text(document.displayURL?.deletingLastPathComponent().path(percentEncoded: false) ?? "Not yet saved")
                    .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minWidth: 110, maxWidth: 360, alignment: .leading)
            .layoutPriority(1)

            Spacer()

            ViewThatFits(in: .horizontal) {
                WorkspaceModeControl()
                WorkspaceModeControl(compact: true)
            }

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

            ExportMenu()
            MoreActionsMenu()
        }
        .buttonStyle(.borderless)
        .padding(.leading, hasLeadingNavigationPane ? 12 : 76)
        .padding(.trailing, 12)
        .frame(height: 52)
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.018 : 0.008))
        .animation(reduceMotion ? nil : MoriMotion.control, value: document.showFileLibrary)
        .animation(reduceMotion ? nil : MoriMotion.control, value: document.showOutline)
    }
}

private struct ExportMenu: View {
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        Menu {
            Button("Export HTML…", systemImage: "globe") { document.exportHTML() }
            Button("Export PDF…", systemImage: "doc.richtext") { document.exportPDF() }
            Divider()
            Button("Print…", systemImage: "printer") { document.printDocument() }
        } label: {
            if document.isExportingDocument {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(document.previewFileURL != nil || !document.isMarkdownDocument || document.isExportingDocument)
        .help(document.isExportingDocument ? "Export in progress" : "Export document")
        .accessibilityLabel(document.isExportingDocument ? "Export in progress" : "Export document")
    }
}

private struct WorkspaceModeControl: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false

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
        Button {
            withMoriAnimation(reduceMotion, action)
        } label: {
            Group {
                if compact {
                    Image(systemName: systemImage)
                } else {
                    Label(title, systemImage: systemImage)
                }
            }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(isActive ? document.theme.accent : .secondary)
                .padding(.horizontal, compact ? 6 : 7)
                .frame(height: 24)
                .background(isActive ? document.theme.background : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : MoriMotion.control, value: isActive)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                Text("Mori")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Spacer()
                Button {
                    withMoriAnimation(reduceMotion) { document.showFileLibrary = false }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless).help("Close file library")
            }
            .padding(.leading, 76).padding(.trailing, 14).frame(height: 52)
            .overlay(alignment: .bottom) { Divider().opacity(0.45) }

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WORKSPACE")
                        .font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
                    Text(document.workspaceURL?.lastPathComponent ?? "No folder open")
                        .font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { document.newDocument() } label: { Image(systemName: "doc.badge.plus") }
                    .help("New document")
                Menu {
                    Button("Open File…", systemImage: "doc") { document.openDocument() }
                    Button(document.workspaceURL == nil ? "Open Folder…" : "Change Folder…",
                           systemImage: "folder") { document.chooseWorkspaceFolder() }
                    if let root = document.workspaceURL {
                        Divider()
                        Button("New Markdown File", systemImage: "doc.badge.plus") {
                            document.createMarkdownFile(in: root)
                        }
                        Button("New Folder", systemImage: "folder.badge.plus") {
                            document.createFolder(in: root)
                        }
                        Divider()
                        Button("Search in Folder", systemImage: "doc.text.magnifyingglass") {
                            document.showWorkspaceSearch = true
                        }
                        Button("Refresh", systemImage: "arrow.clockwise") { document.refreshWorkspace() }
                        Button(document.showMarkdownOnly ? "Show All Files" : "Show Markdown Only",
                               systemImage: "line.3.horizontal.decrease.circle") {
                            document.showMarkdownOnly.toggle()
                        }
                        Divider()
                        Button("Close Folder", systemImage: "xmark.circle") { document.closeWorkspaceFolder() }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Workspace actions")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .padding(.horizontal, 14)
            .frame(height: 66)

            if let root = document.workspaceURL {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Filter files", text: $workspaceQuery)
                        .textFieldStyle(.plain)
                    if document.isLoadingWorkspace {
                        ProgressView().controlSize(.mini)
                    } else if !workspaceQuery.isEmpty {
                        Button { workspaceQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 10.5))
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12).padding(.bottom, 8)

                List(selection: $workspaceSelection) {
                    Group {
                        if filteredWorkspaceTree.isEmpty {
                            SidebarEmptyState(
                                systemImage: workspaceQuery.isEmpty ? "folder" : "doc.text.magnifyingglass",
                                title: workspaceQuery.isEmpty ? "This folder is empty" : "No matching files",
                                detail: workspaceQuery.isEmpty ? "Create a document to get started." : "Try a different file name."
                            )
                        } else {
                            OutlineGroup(filteredWorkspaceTree, children: \.children) { node in
                                WorkspaceNodeRow(
                                    node: node,
                                    root: root,
                                    isSelected: workspaceSelection.contains(node.id),
                                    draggedURLs: workspaceSelection.contains(node.id) ? selectedWorkspaceURLs : [node.url],
                                    onDrop: { providers in acceptDrop(providers, into: node.url) }
                                )
                                .tag(node.id)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7)
                .onDrop(of: WorkspaceTransfer.dropTypes, isTargeted: nil) { providers in
                    acceptDrop(providers, into: root)
                }
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
            } else {
                SidebarEmptyState(
                    systemImage: "folder.badge.plus",
                    title: "No folder open",
                    detail: "Open a folder to browse and manage its files.",
                    actionTitle: "Open Folder",
                    action: document.chooseWorkspaceFolder
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("RECENT")
                        .font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
                    Spacer()
                    if !document.recentFiles.isEmpty {
                        Button("Clear") { document.clearRecentFiles() }
                            .buttonStyle(.plain).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 4)

                if document.recentFiles.isEmpty {
                    Text("Files you open will appear here.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                } else {
                    ForEach(document.recentFiles.prefix(3), id: \.path) { url in
                        RecentFileRow(url: url)
                    }
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 9)
            .overlay(alignment: .top) { Divider().opacity(0.45) }

            HStack(spacing: 8) {
                Text("\(document.workspaceFiles.count) files")
                Spacer()
                Text(document.showMarkdownOnly ? "Markdown only" : "All files")
            }
            .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.tertiary)
            .padding(.horizontal, 13).frame(height: 28)
            .overlay(alignment: .top) { Divider().opacity(0.45) }
        }
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.06 : 0.045))
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

private struct SidebarEmptyState: View {
    @EnvironmentObject private var document: DocumentStore
    let systemImage: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(document.theme.accent.opacity(0.75))
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(document.theme.accent)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 15)
    }
}

private struct QuietRowSurface: ViewModifier {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isSelected: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(surfaceColor)
            }
            .onHover { hovering in
                if reduceMotion {
                    isHovered = hovering
                } else {
                    withAnimation(MoriMotion.fast) { isHovered = hovering }
                }
            }
            .animation(reduceMotion ? nil : MoriMotion.fast, value: isSelected)
    }

    private var surfaceColor: Color {
        if isSelected {
            return document.theme.accent.opacity(document.theme.isDark ? 0.18 : 0.10)
        }
        if isHovered {
            return document.theme.foreground.opacity(document.theme.isDark ? 0.07 : 0.045)
        }
        return .clear
    }
}

private extension View {
    func quietRowSurface(isSelected: Bool = false) -> some View {
        modifier(QuietRowSurface(isSelected: isSelected))
    }
}

private struct OutlinePane: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var scrollSync: ScrollSyncState

    private var currentHeadingLine: Int? {
        document.headings.last(where: { $0.line <= scrollSync.position.line })?.line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("OUTLINE")
                    .font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text("\(document.headings.count)")
                    .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.tertiary)
                Button {
                    withMoriAnimation(reduceMotion) { document.showOutline = false }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.borderless).help("Close document outline")
            }
            .padding(.leading, document.showFileLibrary ? 14 : 76)
            .padding(.trailing, 14)
            .frame(height: 52)

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
                        .quietRowSurface(isSelected: currentHeadingLine == heading.line)
                        .help("Level \(heading.level) · line \(heading.line + 1)")
                    }
                }
                .padding(.horizontal, 5).padding(.vertical, 7)
            }

            HStack(spacing: 7) {
                Circle().fill(document.theme.accent).frame(width: 5, height: 5)
                Text("Select a heading to sync source and preview")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .overlay(alignment: .top) { Divider().opacity(0.4) }
        }
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.04 : 0.024))
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
        .quietRowSurface(isSelected: document.displayURL?.standardizedFileURL == url.standardizedFileURL)
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
    let isSelected: Bool
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
            .quietRowSurface(isSelected: isSelected)
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
            WorkspaceFileRow(url: node.url, root: root, showParent: false,
                             isSelected: isSelected, draggedURLs: draggedURLs)
        }
    }
}

private struct WorkspaceFileRow: View {
    @EnvironmentObject private var document: DocumentStore
    let url: URL
    let root: URL
    var showParent = true
    var isSelected = false
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
        .quietRowSurface(isSelected: isSelected || document.displayURL?.standardizedFileURL == url.standardizedFileURL)
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
        ViewThatFits(in: .horizontal) {
            statusContent(compact: false)
            statusContent(compact: true)
        }
        .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).frame(height: 28)
        .background(document.theme.foreground.opacity(document.theme.isDark ? 0.018 : 0.008))
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }

    @ViewBuilder
    private func statusContent(compact: Bool) -> some View {
        HStack(spacing: 15) {
            Label(document.isDirty ? "Edited" : "Saved", systemImage: document.isDirty ? "circle.fill" : "checkmark.circle")
                .labelStyle(.titleAndIcon)
            Spacer()
            if let url = document.previewFileURL {
                Text(url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased())
                if !compact {
                    Text(document.isImageFile(url) ? "Mori image preview" : "System preview")
                }
            } else {
                Text(document.readerMode ? "Reader" : document.documentFormat.label)
                if !compact {
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
                }
                if let selection = document.selectionStats {
                    Text("\(selection.characters) selected")
                }
                if !compact {
                    Text("\(document.stats.characters) characters")
                }
                Text("\(document.stats.words) words")
            }
        }
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
