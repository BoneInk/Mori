import AppKit
import WebKit

@MainActor
final class MarkdownFileExporter: NSObject, WKNavigationDelegate {
    enum Operation {
        case pdf(URL)
        case printDocument

        var isPrint: Bool {
            if case .printDocument = self { return true }
            return false
        }
    }

    private let operation: Operation
    private let completion: (Result<URL?, Error>) -> Void
    private var webView: WKWebView!

    init(html: String, baseURL: URL?, operation: Operation, completion: @escaping (Result<URL?, Error>) -> Void) {
        self.operation = operation
        self.completion = completion
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123), configuration: configuration)
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("if(window.moriRenderAll){window.moriRenderAll()} true") { [weak self] _, _ in
            self?.waitForEnhancements(remainingAttempts: 100)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func waitForEnhancements(remainingAttempts: Int) {
        webView.evaluateJavaScript("window.moriEnhancementsDone !== false && window.moriMermaidDone !== false && window.moriMathDone !== false && (!window.moriLayoutStable || window.moriLayoutStable())") { [weak self] value, _ in
            guard let self else { return }
            if value as? Bool == true || remainingAttempts <= 0 {
                self.performOperation()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.waitForEnhancements(remainingAttempts: remainingAttempts - 1)
                }
            }
        }
    }

    private func performOperation() {
        switch operation {
        case .pdf(let url):
            let configuration = WKPDFConfiguration()
            webView.createPDF(configuration: configuration) { [weak self] result in
                do {
                    let data = try result.get()
                    try data.write(to: url, options: .atomic)
                    self?.finish(.success(url))
                } catch {
                    self?.finish(.failure(error))
                }
            }
        case .printDocument:
            let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            let printOperation = webView.printOperation(with: printInfo)
            printOperation.showsPrintPanel = true
            printOperation.showsProgressPanel = true
            if printOperation.run() {
                finish(.success(nil))
            } else {
                finish(.failure(CocoaError(.userCancelled)))
            }
        }
    }

    private func finish(_ result: Result<URL?, Error>) {
        webView.navigationDelegate = nil
        completion(result)
    }
}
