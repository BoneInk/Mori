import AppKit
import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var command: EditorCommand?
    @Binding var scrollPosition: ScrollPosition
    @Binding var scrollSource: ScrollSource
    let theme: EditorTheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = UserTrackingScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 56, height: 48)
        textView.font = .systemFont(ofSize: 16.5)
        textView.string = text
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        scrollView.onUserScroll = { [weak coordinator = context.coordinator] in
            coordinator?.requestScrollUpdate()
        }
        context.coordinator.startObservingScroll()
        applyTheme(textView)
        context.coordinator.highlight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
            context.coordinator.highlight()
        }
        applyTheme(textView)
        if context.coordinator.lastTheme != theme {
            context.coordinator.lastTheme = theme
            context.coordinator.highlight()
        }
        if scrollSource == .preview || scrollSource == .outline {
            context.coordinator.scroll(to: scrollPosition)
        }
        if let command {
            if context.coordinator.lastAppliedCommand != command {
                context.coordinator.lastAppliedCommand = command
                context.coordinator.apply(command)
            }
            DispatchQueue.main.async { self.command = nil }
        } else {
            context.coordinator.lastAppliedCommand = nil
        }
    }

    private func applyTheme(_ textView: NSTextView) {
        textView.backgroundColor = NSColor(theme.background)
        textView.textColor = NSColor(theme.foreground)
        textView.insertionPointColor = NSColor(theme.accent)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(theme.accent).withAlphaComponent(0.22),
            .foregroundColor: NSColor(theme.foreground)
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var lastTheme: EditorTheme?
        var lastAppliedCommand: EditorCommand?
        private var isHighlighting = false
        private var scrollObserver: NSObjectProtocol?
        private var lineOffsets: [Int] = [0]
        private var lineOffsetsTextLength = -1
        private var lastScrollPublish = 0.0
        private var pendingScrollUpdate: DispatchWorkItem?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        deinit {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        func startObservingScroll() {
            guard let scrollView else { return }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.requestScrollUpdate()
            }
        }

        func requestScrollUpdate() {
            let interval = 1.0 / 30.0
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - lastScrollPublish
            if elapsed >= interval {
                pendingScrollUpdate?.cancel()
                pendingScrollUpdate = nil
                lastScrollPublish = now
                editorDidScroll()
            } else if pendingScrollUpdate == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingScrollUpdate = nil
                    self.lastScrollPublish = ProcessInfo.processInfo.systemUptime
                    self.editorDidScroll()
                }
                pendingScrollUpdate = work
                DispatchQueue.main.asyncAfter(deadline: .now() + interval - elapsed, execute: work)
            }
        }

        private func editorDidScroll() {
            guard let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            rebuildLineOffsetsIfNeeded()
            let containerY = max(0, scrollView.contentView.bounds.minY - textView.textContainerOrigin.y)
            var glyphFraction: CGFloat = 0
            let glyph = layoutManager.glyphIndex(for: NSPoint(x: 1, y: containerY),
                                                 in: textContainer,
                                                 fractionOfDistanceThroughGlyph: &glyphFraction)
            let character = min(layoutManager.characterIndexForGlyph(at: glyph), max(0, (textView.string as NSString).length - 1))
            let line = lineNumber(for: character)
            let start = lineOffsets[min(line, lineOffsets.count - 1)]
            let end = line + 1 < lineOffsets.count ? lineOffsets[line + 1] : (textView.string as NSString).length
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: max(1, end - start)), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let fraction = rect.height > 1 ? Double((containerY - rect.minY) / rect.height) : 0
            let position = ScrollPosition(line: line, fraction: min(1, max(0, fraction)))
            guard position != parent.scrollPosition || parent.scrollSource != .editor else { return }
            parent.scrollSource = .editor
            parent.scrollPosition = position
        }

        func scroll(to position: ScrollPosition) {
            guard let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            rebuildLineOffsetsIfNeeded()
            let line = min(max(0, position.line), lineOffsets.count - 1)
            let start = lineOffsets[line]
            let end = line + 1 < lineOffsets.count ? lineOffsets[line + 1] : (textView.string as NSString).length
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: max(1, end - start)), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let requested = textView.textContainerOrigin.y + rect.minY + CGFloat(min(1, max(0, position.fraction))) * rect.height
            let maximum = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
            let target = min(maximum, max(0, requested))
            guard abs(scrollView.contentView.bounds.minY - target) > 1 else { return }
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: target))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func rebuildLineOffsetsIfNeeded() {
            guard let textView else { return }
            let length = (textView.string as NSString).length
            guard lineOffsetsTextLength != length else { return }
            lineOffsets = [0]
            for (index, unit) in textView.string.utf16.enumerated() where unit == 10 {
                lineOffsets.append(index + 1)
            }
            lineOffsetsTextLength = length
        }

        private func lineNumber(for character: Int) -> Int {
            var low = 0
            var high = lineOffsets.count
            while low < high {
                let middle = (low + high) / 2
                if lineOffsets[middle] <= character { low = middle + 1 } else { high = middle }
            }
            return max(0, low - 1)
        }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting, let textView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
                highlight()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let range = textView.selectedRange()
            if parent.selection != range { parent.selection = range }
        }

        func apply(_ command: EditorCommand) {
            guard let textView else { return }
            switch command {
            case .insert(let prefix):
                let range = textView.selectedRange()
                let nsText = textView.string as NSString
                let lineRange = nsText.lineRange(for: range)
                textView.insertText(prefix, replacementRange: NSRange(location: lineRange.location, length: 0))
                textView.setSelectedRange(NSRange(location: range.location + (prefix as NSString).length, length: range.length))
            case .wrap(let left, let right, let placeholder):
                let range = textView.selectedRange()
                let selected = range.length > 0 ? (textView.string as NSString).substring(with: range) : placeholder
                let replacement = left + selected + right
                textView.insertText(replacement, replacementRange: range)
                textView.setSelectedRange(NSRange(location: range.location + (left as NSString).length, length: (selected as NSString).length))
            case .select(let range):
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
                textView.window?.makeFirstResponder(textView)
            }
            if parent.text != textView.string {
                parent.text = textView.string
                highlight()
            }
        }

        func highlight() {
            guard let textView, let storage = textView.textStorage else { return }
            isHighlighting = true
            lineOffsets = [0]
            for (index, unit) in textView.string.utf16.enumerated() where unit == 10 {
                lineOffsets.append(index + 1)
            }
            lineOffsetsTextLength = (textView.string as NSString).length
            let whole = NSRange(location: 0, length: storage.length)
            let base = NSColor(parent.theme.foreground)
            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.systemFont(ofSize: 16.5),
                .foregroundColor: base,
                .paragraphStyle: paragraphStyle()
            ], range: whole)
            apply(#"(?m)^(#{1,6})\s+(.+)$"#, color: NSColor(parent.theme.foreground), font: .systemFont(ofSize: 19, weight: .bold), storage: storage)
            apply(#"(?s)```.*?```"#, color: NSColor(parent.theme.accent), font: .monospacedSystemFont(ofSize: 14, weight: .regular), storage: storage)
            apply(#"`[^`\n]+`"#, color: NSColor(parent.theme.accent), font: .monospacedSystemFont(ofSize: 14, weight: .regular), storage: storage)
            apply(#"(?m)</?[A-Za-z][^>\n]*>"#, color: NSColor(parent.theme.accent), font: .monospacedSystemFont(ofSize: 14, weight: .regular), storage: storage)
            apply(#"(?m)^(>|-|\*|\d+\.)\s"#, color: NSColor(parent.theme.accent), font: .systemFont(ofSize: 16.5, weight: .semibold), storage: storage)
            storage.endEditing()
            isHighlighting = false
        }

        private func apply(_ pattern: String, color: NSColor, font: NSFont, storage: NSTextStorage) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(location: 0, length: storage.length)
            regex.enumerateMatches(in: storage.string, range: range) { result, _, _ in
                guard let result else { return }
                storage.addAttributes([.foregroundColor: color, .font: font], range: result.range)
            }
        }

        private func paragraphStyle() -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 5
            style.paragraphSpacing = 3
            return style
        }
    }
}

private final class UserTrackingScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        DispatchQueue.main.async { [weak self] in self?.onUserScroll?() }
    }
}
