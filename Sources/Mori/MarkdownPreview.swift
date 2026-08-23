import SwiftUI
import WebKit

struct MarkdownPreview: NSViewRepresentable {
    let markdown: String
    let revision: Int
    let title: String
    let theme: EditorTheme
    let baseURL: URL?
    @Binding var scrollPosition: ScrollPosition
    @Binding var scrollSource: ScrollSource

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = UserTrackingWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.signature = signature
        context.coordinator.webView = view
        view.onUserScroll = { [weak coordinator = context.coordinator] in
            coordinator?.requestScrollUpdate()
        }
        context.coordinator.startObservingScroll()
        load(view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        if signature != context.coordinator.signature {
            context.coordinator.signature = signature
            context.coordinator.pendingPosition = scrollPosition
            load(view)
        } else if scrollSource == .editor || scrollSource == .outline {
            context.coordinator.scroll(view, to: scrollPosition)
        }
    }

    private var signature: String { "\(theme.rawValue):\(revision):\(baseURL?.path ?? "")" }

    private func load(_ view: WKWebView) {
        view.loadHTMLString(MarkdownRenderer.document(markdown: markdown, title: title, theme: theme), baseURL: baseURL)
    }

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

        deinit {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
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
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.scroll(webView, to: position, force: true)
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
                NSWorkspace.shared.open(url)
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
