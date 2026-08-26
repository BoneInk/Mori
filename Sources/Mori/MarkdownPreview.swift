import SwiftUI
import UniformTypeIdentifiers
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
        let localResourceHandler = LocalPreviewResourceHandler()
        config.setURLSchemeHandler(localResourceHandler, forURLScheme: LocalPreviewResources.scheme)
        let view = UserTrackingWebView(frame: .zero, configuration: config)
        view.setAccessibilityLabel("Rendered Markdown preview")
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.signature = signature
        context.coordinator.documentLength = (markdown as NSString).length
        context.coordinator.webView = view
        context.coordinator.localResourceHandler = localResourceHandler
        view.onUserScroll = { [weak coordinator = context.coordinator] in
            coordinator?.requestScrollUpdate(userInitiated: true)
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
            context.coordinator.documentLength = (markdown as NSString).length
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
        fileprivate var localResourceHandler: LocalPreviewResourceHandler?
        private var lastAppliedPosition = ScrollPosition(line: -1, fraction: -1)
        private var scrollObserver: NSObjectProtocol?
        private var lastScrollPublish = 0.0
        private var pendingScrollUpdate: DispatchWorkItem?
        private var scrollRequestGeneration = 0
        private var suppressScrollEventsUntil = 0.0
        fileprivate var documentLength = 0
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
                    let rendered = MarkdownRenderer.document(markdown: markdown, title: title, theme: theme, typography: typography)
                    return LocalPreviewResources.rewriteLocalMedia(in: rendered, baseURL: baseURL)
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
                self.localResourceHandler?.setAllowedRoot(baseURL)
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
                Task { @MainActor in self?.requestScrollUpdate(userInitiated: false) }
            }
        }

        func requestScrollUpdate(userInitiated: Bool) {
            let interval = documentLength > 750_000 ? 1.0 / 10.0 : (documentLength > 150_000 ? 1.0 / 15.0 : 1.0 / 30.0)
            let now = ProcessInfo.processInfo.systemUptime
            if userInitiated {
                suppressScrollEventsUntil = 0
            } else if now < suppressScrollEventsUntil {
                return
            }
            if parent?.scrollSource != .preview { parent?.scrollSource = .preview }
            scrollRequestGeneration &+= 1
            let generation = scrollRequestGeneration
            let elapsed = now - lastScrollPublish
            if elapsed >= interval {
                pendingScrollUpdate?.cancel()
                pendingScrollUpdate = nil
                lastScrollPublish = now
                previewDidScroll(generation: generation)
            } else {
                pendingScrollUpdate?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingScrollUpdate = nil
                    self.lastScrollPublish = ProcessInfo.processInfo.systemUptime
                    self.previewDidScroll(generation: generation)
                }
                pendingScrollUpdate = work
                DispatchQueue.main.asyncAfter(deadline: .now() + interval - elapsed, execute: work)
            }
        }

        private func previewDidScroll(generation: Int) {
            guard generation == scrollRequestGeneration,
                  let parent,
                  parent.scrollSource == .preview,
                  ProcessInfo.processInfo.systemUptime >= suppressScrollEventsUntil,
                  let webView else { return }
            webView.evaluateJavaScript("window.moriCurrentPosition && window.moriCurrentPosition()") { [weak self] value, _ in
                guard let self,
                      generation == self.scrollRequestGeneration,
                      let parent = self.parent,
                      parent.scrollSource == .preview,
                      ProcessInfo.processInfo.systemUptime >= self.suppressScrollEventsUntil,
                      let result = value as? [String: Any],
                      let line = result["line"] as? Int,
                      let fraction = result["fraction"] as? Double else { return }
                let position = ScrollPosition(line: line, fraction: min(1, max(0, fraction)))
                guard position != parent.scrollPosition || parent.scrollSource != .preview else { return }
                parent.scrollPosition = position
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
            pendingScrollUpdate?.cancel()
            pendingScrollUpdate = nil
            scrollRequestGeneration &+= 1
            suppressScrollEventsUntil = ProcessInfo.processInfo.systemUptime + 0.12
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

private enum LocalPreviewResources {
    static let scheme = "mori-local"

    static func rewriteLocalMedia(in html: String, baseURL: URL?) -> String {
        guard let baseURL = baseURL?.standardizedFileURL,
              baseURL.isFileURL,
              let regex = try? NSRegularExpression(pattern: #"(?i)\b(?:src|poster)\s*=\s*\"([^\"]+)\""#) else {
            return html
        }

        let source = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: source.length))
        var result = html
        for match in matches.reversed() {
            let valueRange = match.range(at: 1)
            guard valueRange.location != NSNotFound else { continue }
            let escapedValue = source.substring(with: valueRange)
            let value = decodeHTMLEntities(escapedValue)
            guard let replacement = localResourceURL(for: value, baseURL: baseURL),
                  let range = Range(valueRange, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func localResourceURL(for value: String, baseURL: URL) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix("//"),
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              let parsed = URLComponents(string: trimmed),
              parsed.scheme == nil,
              parsed.host == nil else { return nil }

        let encodedPath = parsed.percentEncodedPath
        let relativePath = encodedPath.removingPercentEncoding ?? parsed.path
        guard !relativePath.isEmpty else { return nil }
        let target = baseURL.appendingPathComponent(relativePath).standardizedFileURL
        guard isInside(target, root: baseURL) else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = "resource"
        components.path = target.path
        return components.string
    }

    static func fileURL(from resourceURL: URL, allowedRoot: URL?) -> URL? {
        guard resourceURL.scheme == scheme,
              resourceURL.host == "resource",
              let root = allowedRoot?.resolvingSymlinksInPath().standardizedFileURL else { return nil }
        let target = URL(fileURLWithPath: resourceURL.path(percentEncoded: false))
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return isInside(target, root: root) ? target : nil
    }

    private static func isInside(_ file: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

private final class LocalPreviewResourceHandler: NSObject, WKURLSchemeHandler {
    private let stateLock = NSLock()
    private var allowedRoot: URL?
    private var activeTasks = Set<ObjectIdentifier>()

    func setAllowedRoot(_ root: URL?) {
        stateLock.lock()
        allowedRoot = root?.resolvingSymlinksInPath().standardizedFileURL
        stateLock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask)
        stateLock.lock()
        activeTasks.insert(identifier)
        let root = allowedRoot
        stateLock.unlock()

        guard let requestURL = urlSchemeTask.request.url,
              let fileURL = LocalPreviewResources.fileURL(from: requestURL, allowedRoot: root) else {
            finish(urlSchemeTask, identifier: identifier,
                   result: .failure(URLError(.noPermissionsToReadFile)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<(Data, String), Error>
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                result = .success((data, mimeType))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { [weak self] in
                self?.finish(urlSchemeTask, identifier: identifier, result: result)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        stateLock.lock()
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
        stateLock.unlock()
    }

    private func finish(_ task: any WKURLSchemeTask,
                        identifier: ObjectIdentifier,
                        result: Result<(Data, String), Error>) {
        stateLock.lock()
        let isActive = activeTasks.remove(identifier) != nil
        stateLock.unlock()
        guard isActive else { return }

        switch result {
        case let .success((data, mimeType)):
            let response = URLResponse(url: task.request.url!,
                                       mimeType: mimeType,
                                       expectedContentLength: data.count,
                                       textEncodingName: nil)
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        case let .failure(error):
            task.didFailWithError(error)
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
