import SwiftUI
import WebKit

struct MarkdownPreview: NSViewRepresentable {
    let markdown: String
    let revision: Int
    let title: String
    let theme: EditorTheme
    let typography: TypographySettings
    let baseURL: URL?
    let onOpenLocalFile: (URL) -> Void
    @Binding var scrollPosition: ScrollPosition
    @Binding var scrollSource: ScrollSource

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = UserTrackingWebView(frame: .zero, configuration: config)
        view.setAccessibilityLabel("Rendered Markdown preview")
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.signature = signature
        context.coordinator.webView = view
        view.onUserScroll = { [weak coordinator = context.coordinator] in
            coordinator?.requestScrollUpdate()
        }
        context.coordinator.startObservingScroll()
        context.coordinator.scheduleLoad(markdown: markdown,
                                         title: title,
                                         theme: theme,
                                         typography: typography,
                                         baseURL: baseURL,
                                         containsMermaid: containsMermaidDiagram,
                                         containsMath: containsMathExpression,
                                         expectedSignature: signature,
                                         debounce: false)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        if signature != context.coordinator.signature {
            context.coordinator.signature = signature
            context.coordinator.pendingPosition = scrollPosition
            context.coordinator.scheduleLoad(markdown: markdown,
                                             title: title,
                                             theme: theme,
                                             typography: typography,
                                             baseURL: baseURL,
                                             containsMermaid: containsMermaidDiagram,
                                             containsMath: containsMathExpression,
                                             expectedSignature: signature,
                                             debounce: true)
        } else if scrollSource == .editor || scrollSource == .outline {
            context.coordinator.scroll(view, to: scrollPosition)
        }
    }

    private var signature: String { "\(theme.hashValue):\(typography.hashValue):\(revision):\(baseURL?.path ?? "")" }

    private var containsMermaidDiagram: Bool {
        markdown.range(of: #"(?m)^\s*(?:```|~~~)(?:mermaid|mmd)(?:\s.*)?$"#, options: .regularExpression) != nil
    }

    private var containsMathExpression: Bool {
        markdown.range(of: #"(?m)^\s*(?:\$\$|\\\[)\s*$|(?<!\\)\$(?!\s)[^$\n]+?(?<!\s|\\)\$"#,
                       options: .regularExpression) != nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var signature = ""
        var pendingPosition: ScrollPosition?
        var parent: MarkdownPreview?
        weak var webView: WKWebView?
        weak var previewScrollView: NSScrollView?
        private var lastAppliedPosition = ScrollPosition(line: -1, fraction: -1)
        private var scrollObserver: NSObjectProtocol?
        private var lastScrollPublish = 0.0
        private var pendingScrollUpdate: DispatchWorkItem?
        private var renderTask: Task<Void, Never>?

        deinit {
            renderTask?.cancel()
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        func scheduleLoad(markdown: String,
                          title: String,
                          theme: EditorTheme,
                          typography: TypographySettings,
                          baseURL: URL?,
                          containsMermaid: Bool,
                          containsMath: Bool,
                          expectedSignature: String,
                          debounce: Bool) {
            renderTask?.cancel()
            renderTask = Task { [weak self, weak webView] in
                if debounce { try? await Task.sleep(for: .milliseconds(85)) }
                guard !Task.isCancelled else { return }
                let html = await Task.detached(priority: .userInitiated) {
                    MarkdownRenderer.document(markdown: markdown, title: title, theme: theme, typography: typography)
                }.value
                guard !Task.isCancelled,
                      let self,
                      self.signature == expectedSignature,
                      let webView else { return }
                let controller = webView.configuration.userContentController
                controller.removeAllUserScripts()
                if containsMermaid, let script = MermaidRuntime.script {
                    controller.addUserScript(
                        WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
                    )
                }
                if containsMath, let script = MathRuntime.script {
                    controller.addUserScript(
                        WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
                    )
                }
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func startObservingScroll() {
            guard let webView,
                  let scrollView = findScrollView(in: webView) else { return }
            previewScrollView = scrollView
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.requestScrollUpdate() }
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
                previewDidScroll()
            } else if pendingScrollUpdate == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingScrollUpdate = nil
                    self.lastScrollPublish = ProcessInfo.processInfo.systemUptime
                    self.previewDidScroll()
                }
                pendingScrollUpdate = work
                DispatchQueue.main.asyncAfter(deadline: .now() + interval - elapsed, execute: work)
            }
        }

        private func previewDidScroll() {
            guard let parent, let webView else { return }
            webView.evaluateJavaScript("window.moriCurrentPosition && window.moriCurrentPosition()") { [weak self] value, _ in
                guard let self,
                      let result = value as? [String: Any],
                      let line = result["line"] as? Int,
                      let fraction = result["fraction"] as? Double else { return }
                let position = ScrollPosition(line: line, fraction: min(1, max(0, fraction)))
                guard position != parent.scrollPosition || parent.scrollSource != .preview else { return }
                self.parent?.scrollSource = .preview
                self.parent?.scrollPosition = position
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if scrollObserver == nil { startObservingScroll() }
            let position = pendingPosition ?? parent?.scrollPosition ?? ScrollPosition()
            pendingPosition = nil
            webView.evaluateJavaScript("if(window.moriRenderAll){window.moriRenderAll()} true") { [weak self, weak webView] _, _ in
                guard let self, let webView else { return }
                self.waitForEnhancements(in: webView, position: position, remainingAttempts: 80)
            }
        }

        private func waitForEnhancements(in webView: WKWebView, position: ScrollPosition, remainingAttempts: Int) {
            webView.evaluateJavaScript("window.moriMermaidDone !== false && window.moriMathDone !== false") { [weak self, weak webView] value, _ in
                guard let self, let webView else { return }
                if value as? Bool == true || remainingAttempts <= 0 {
                    DispatchQueue.main.async { [weak self, weak webView] in
                        guard let self, let webView else { return }
                        self.scroll(webView, to: position, force: true)
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak webView] in
                        guard let self, let webView else { return }
                        self.waitForEnhancements(in: webView, position: position, remainingAttempts: remainingAttempts - 1)
                    }
                }
            }
        }

        func scroll(_ webView: WKWebView, to position: ScrollPosition, force: Bool = false) {
            guard force || position != lastAppliedPosition else { return }
            lastAppliedPosition = position
            webView.evaluateJavaScript("window.moriScrollToLine && window.moriScrollToLine(\(position.line), \(min(1, max(0, position.fraction))))")
        }

        private func findScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView { return scrollView }
            for subview in view.subviews {
                if let match = findScrollView(in: subview) { return match }
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if url.fragment != nil {
                    decisionHandler(.allow)
                    return
                }
                if url.isFileURL {
                    parent?.onOpenLocalFile(url)
                } else {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

private final class UserTrackingWebView: WKWebView {
    var onUserScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        DispatchQueue.main.async { [weak self] in self?.onUserScroll?() }
    }
}
