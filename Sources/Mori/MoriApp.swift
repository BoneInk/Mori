import SwiftUI

@main
struct MoriApp: App {
    @StateObject private var document = DocumentStore()

    var body: some Scene {
        Window("Mori", id: "main") {
            ContentView()
                .environmentObject(document)
                .frame(minWidth: 1120, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document") { document.newDocument() }
                    .keyboardShortcut("n")
                Button("Open…") { document.openDocument() }
                    .keyboardShortcut("o")
                Divider()
                Button("Save") { document.save() }
                    .keyboardShortcut("s")
                Button("Save As…") { document.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Export HTML…") { document.exportHTML() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil || document.isExportingDocument)
                Button("Export PDF…") { document.exportPDF() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil || document.isExportingDocument)
                Button("Print…") { document.printDocument() }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil || document.isExportingDocument)
            }
            CommandMenu("View") {
                Button("Toggle Navigation") { document.toggleNavigation() }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Toggle File Library") {
                    document.showFileLibrary.toggle(); document.showSidebar = true
                }
                Button("Toggle Document Outline") {
                    document.showOutline.toggle(); document.showSidebar = true
                }
                Button("Toggle Preview") { document.showPreview.toggle() }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Focus Mode") { document.focusMode.toggle() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Button("Reader Mode") { document.toggleReaderMode() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu("Navigate") {
                Button("Command Palette…") { document.showCommandPalette = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Quick Open…") { document.showQuickOpen = true }
                    .keyboardShortcut("p")
                Button("Search in Folder…") { document.showWorkspaceSearch = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button("Find in Document…") { document.showFind() }
                    .keyboardShortcut("f")
                    .disabled(document.previewFileURL != nil || document.readerMode)
                Button("Find and Replace…") { document.showReplace() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(document.previewFileURL != nil || document.readerMode)
                Button("Go to Line…") { document.goToLine() }
                    .keyboardShortcut("g", modifiers: [.control])
                    .disabled(document.previewFileURL != nil || document.readerMode)
                Button("Document History…") { document.showDocumentHistory = true }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(document.fileURL == nil || document.previewFileURL != nil)
                Divider()
                Button("Previous Tab") { document.selectNextTab(offset: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(document.openTabs.count < 2)
                Button("Next Tab") { document.selectNextTab(offset: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(document.openTabs.count < 2)
                Button("Close Tab") {
                    if let id = document.activeTabID { document.closeTab(id) }
                }
                .keyboardShortcut("w")
            }
            CommandMenu("Format") {
                Button("Heading") { document.insert(prefix: "## ") }
                    .keyboardShortcut("2", modifiers: [.command])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Bold") { document.wrapSelection(left: "**", right: "**", placeholder: "bold text") }
                    .keyboardShortcut("b")
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Italic") { document.wrapSelection(left: "_", right: "_", placeholder: "italic text") }
                    .keyboardShortcut("i")
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Inline Code") { document.wrapSelection(left: "`", right: "`", placeholder: "code") }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Strikethrough") { document.wrapSelection(left: "~~", right: "~~", placeholder: "struck text") }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Link") { document.wrapSelection(left: "[", right: "](https://)", placeholder: "link text") }
                    .keyboardShortcut("k")
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Insert Image…") { document.chooseImagesToInsert() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil || document.readerMode)
                Divider()
                Button("Bulleted List") { document.insert(prefix: "- ") }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Numbered List") { document.insert(prefix: "1. ") }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Block Quote") { document.insert(prefix: "> ") }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Table…") { document.showTableBuilder = true }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil || document.readerMode)
                Divider()
                Button("Inline Math") { document.wrapSelection(left: "$", right: "$", placeholder: "E = mc^2") }
                    .keyboardShortcut("m", modifiers: [.command, .control])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Display Math") { document.wrapSelection(left: "$$\n", right: "\n$$", placeholder: "\\int_0^1 x^2\\,dx") }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button("Fenced Code Block") { document.wrapSelection(left: "```text\n", right: "\n```", placeholder: "code") }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
            }
            CommandMenu("Appearance") {
                ForEach(document.availableThemes) { theme in
                    Button {
                        document.selectTheme(theme)
                    } label: {
                        if document.theme.id == theme.id {
                            Label(theme.name, systemImage: "checkmark")
                        } else {
                            Text(theme.name)
                        }
                    }
                }
                Divider()
                SettingsLink { Text("Theme & Typography Settings…") }
            }
        }

        Settings {
            AppearanceSettingsView()
                .environmentObject(document)
        }
    }
}
