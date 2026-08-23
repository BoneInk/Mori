import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var document: DocumentStore
    @State private var isDropTarget = false
    @State private var scrollSync = ScrollSyncState()

    var body: some View {
        ZStack {
            document.theme.background.ignoresSafeArea()

            HStack(spacing: 0) {
                if document.showSidebar && document.showFileLibrary && !document.focusMode {
                    SidebarView()
                        .frame(width: 215)
                    Divider().opacity(0.5)
                }
                if document.showSidebar && document.showOutline && document.previewFileURL == nil && !document.focusMode {
                    OutlinePane(scrollSync: scrollSync)
                        .frame(width: 235)
                    Divider().opacity(0.5)
                }

                VStack(spacing: 0) {
                    TopBar()
                    Divider().opacity(0.45)

                    if let previewURL = document.previewFileURL {
                        ExternalFilePreview(url: previewURL)
                    } else {
                        WritingWorkspace(scrollSync: scrollSync)
                    }

                    StatusBar()
                }
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
        .preferredColorScheme(document.theme == .midnight ? .dark : .light)
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
                               theme: document.theme)
                    .frame(minWidth: 360)
            }

            if document.readerMode || (document.showPreview && !document.focusMode) {
                MarkdownPreview(markdown: document.text,
                                revision: document.textRevision,
                                title: document.title,
                                theme: document.theme,
                                baseURL: document.fileURL?.deletingLastPathComponent(),
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
        HStack(spacing: 10) {
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

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(document.title).font(.system(size: 13, weight: .semibold))
                    if document.isDirty { Circle().fill(document.theme.accent).frame(width: 5, height: 5) }
                }
                Text(document.displayURL?.deletingLastPathComponent().path(percentEncoded: false) ?? "Not yet saved")
                    .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            Picker("Theme", selection: $document.theme) {
                ForEach(EditorTheme.allCases) { theme in Text(theme.rawValue).tag(theme) }
            }
            .labelsHidden().pickerStyle(.menu).frame(width: 88)

            Button { document.focusMode.toggle() } label: {
                Image(systemName: document.focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .help("Focus mode")

            Button { document.toggleReaderMode() } label: {
                Image(systemName: document.readerMode ? "book.pages.fill" : "book.pages")
            }
            .disabled(document.previewFileURL != nil)
            .help(document.readerMode ? "Exit reader mode" : "Reader mode")

            Button { document.showPreview.toggle() } label: {
                Image(systemName: document.showPreview ? "rectangle.righthalf.inset.filled" : "rectangle")
            }
            .disabled(document.focusMode || document.readerMode || document.previewFileURL != nil)
            .help("Toggle preview")

            Button { document.save() } label: { Image(systemName: "square.and.arrow.down") }
                .disabled(document.previewFileURL != nil)
                .help("Save")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 45)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(document.theme.accent)
                    Image(systemName: "leaf.fill").foregroundStyle(.white).font(.system(size: 13))
                }.frame(width: 28, height: 28)
                Text("Mori").font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button { document.showFileLibrary = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless).help("Close file library")
            }
            .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 20)

            HStack(spacing: 8) {
                SidebarAction(icon: "doc.badge.plus", title: "New") { document.newDocument() }
                SidebarAction(icon: "folder", title: "Open") { document.openDocument() }
            }
            .padding(.horizontal, 12).padding(.bottom, 10)

            Button { document.chooseWorkspaceFolder() } label: {
                Label(document.workspaceURL == nil ? "Open Folder…" : "Change Folder…",
                      systemImage: "folder.badge.plus")
                    .font(.system(size: 10.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.bottom, 12)

            List {
                Group {
                    HStack {
                        Text("FOLDER")
                            .font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
                        Spacer()
                        if document.isLoadingWorkspace {
                            ProgressView().controlSize(.mini)
                        } else if document.workspaceURL != nil {
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
                    .padding(.horizontal, 10).padding(.bottom, 5)

                    if let root = document.workspaceURL {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").foregroundStyle(document.theme.accent)
                            Text(root.lastPathComponent).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text(document.showMarkdownOnly ? "\(document.markdownFileCount)/\(document.workspaceFiles.count)" : "\(document.workspaceFiles.count)")
                                .font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary)
                            Button { document.showMarkdownOnly.toggle() } label: {
                                Image(systemName: document.showMarkdownOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                            .help(document.showMarkdownOnly ? "Show all files" : "Show Markdown files only")
                        }
                        .padding(.horizontal, 10).padding(.bottom, 3)

                        OutlineGroup(document.displayedWorkspaceTree, children: \.children) { node in
                            WorkspaceNodeRow(node: node, root: root)
                        }
                    } else {
                        Text("Open a folder to browse all of its files.")
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 10).padding(.bottom, 8)
                    }

                    Divider().opacity(0.35).padding(.horizontal, 7).padding(.vertical, 10)

                    HStack {
                        Text("RECENT")
                            .font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
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

            Divider().opacity(0.45)
            HStack {
                Image(systemName: "text.book.closed").foregroundStyle(document.theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(document.stats.words) words").font(.system(size: 11, weight: .medium))
                    Text("about \(document.stats.minutes) min read").font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
        }
        .background(document.theme.foreground.opacity(document.theme == .midnight ? 0.035 : 0.025))
    }
}

private struct OutlinePane: View {
    @EnvironmentObject private var document: DocumentStore
    let scrollSync: ScrollSyncState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.indent")
                    .foregroundStyle(document.theme.accent)
                Text("DOCUMENT OUTLINE")
                    .font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(.secondary)
                Spacer()
                Text("\(document.headings.count)")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.primary.opacity(0.06), in: Capsule())
                Button { document.showOutline = false } label: {
                    Image(systemName: "xmark").font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.borderless).help("Close document outline")
            }
            .padding(.horizontal, 14).padding(.top, 18).padding(.bottom, 13)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text("Article structure")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.bottom, 14)

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
                                    .font(.system(size: heading.level == 1 ? 12.5 : 11.5,
                                                  weight: heading.level <= 2 ? .semibold : .regular))
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.leading, CGFloat(min(heading.level - 1, 4)) * 13)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Level \(heading.level) · line \(heading.line + 1)")
                    }
                }
                .padding(.horizontal, 5).padding(.vertical, 7)
            }
        }
        .background(document.theme.foreground.opacity(document.theme == .midnight ? 0.022 : 0.012))
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
        } else {
            WorkspaceFileRow(url: node.url, root: root, showParent: false)
        }
    }
}

private struct WorkspaceFileRow: View {
    @EnvironmentObject private var document: DocumentStore
    let url: URL
    let root: URL
    var showParent = true

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
        Button { document.openWorkspaceFile(url) } label: {
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
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(document.isSupportedDocument(url) ? "Open in Mori" : "Preview in Mori") {
                document.openWorkspaceFile(url)
            }
            if !document.isSupportedDocument(url) {
                Button("Open in Default App") { document.openInDefaultApp(url) }
            }
            Button("Show in Finder") { document.revealInFinder(url) }
        }
        .help(url.path(percentEncoded: false))
    }
}

private struct SidebarAction: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.system(size: 9.5, weight: .medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
                Text("Quick Look preview")
            } else {
                Text(document.readerMode ? "Reader" : "Markdown")
                Text("\(document.stats.characters) characters")
                Text("\(document.stats.words) words")
            }
        }
        .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).frame(height: 26)
    }
}
