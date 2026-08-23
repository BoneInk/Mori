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
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Reader Mode") { document.toggleReaderMode() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu("Format") {
                Button("Heading") { document.insert(prefix: "## ") }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Bold") { document.wrapSelection(left: "**", right: "**", placeholder: "bold text") }
                    .keyboardShortcut("b")
                Button("Italic") { document.wrapSelection(left: "_", right: "_", placeholder: "italic text") }
                    .keyboardShortcut("i")
                Button("Inline Code") { document.wrapSelection(left: "`", right: "`", placeholder: "code") }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
