import AppKit
import Foundation
import WebKit

let markdown = #"""
---
title: Smoke test
---

Market-ready Markdown
=====================

Inline math $E = mc^2$ and a footnote.[^source]

Visit https://example.com and keep [unsafe](javascript:alert(1)) inert.

> [!TIP]
> Theme-aware alert.

## Trailing heading ###

\*literal emphasis markers\* and **strong text**.

`Simple code`, ``code with a ` backtick``, and a [**formatted** link](https://example.com/formatted).

> A multi-line quote
>
> with a second paragraph, `code`, and an inherited [reference][guide].

+ Plus-marker item

3) Ordered from three

- Parent item
  1. Ordered child
     - [x] Nested task
- Sibling item

[Spaced local link](<docs/My File.md>) and ![Remote image](https://example.com/image.png "Example").

* * *

| Left | Center | Right |
| --- | :---: | ---: |
| A | B | C |

[Reference **link**][guide], ![Reference image][logo], and [Shortcut].

[guide]: <docs/Guide File.md> "Guide title"
[logo]: https://example.com/reference.png "Reference logo"
[shortcut]: https://example.com/shortcut

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

~~~mermaid
sequenceDiagram
    User->>Mori: Render
    Mori-->>User: Done
~~~

[^source]: This footnote is rendered locally.
"""#

let html = MarkdownRenderer.document(markdown: markdown,
                                     title: "Renderer smoke test",
                                     theme: .paper,
                                     typography: .standard,
                                     embeddedMermaidScript: MermaidRuntime.script,
                                     embeddedMathScript: MathRuntime.script)

guard html.contains("data-math="),
      html.contains("class=\"footnotes\""),
      html.contains("<h1 data-source-line="),
      html.contains("class=\"front-matter\""),
      html.contains("alert-tip"),
      html.contains("href=\"https://example.com\""),
      html.contains("Trailing heading</h2>"),
      html.contains("*literal emphasis markers*"),
      html.contains("<code>code with a ` backtick</code>"),
      html.contains("href=\"https://example.com/formatted\"><strong>formatted</strong> link</a>"),
      html.contains("<ol start=\"3\" data-source-line="),
      html.contains("href=\"docs/My File.md\""),
      html.contains("alt=\"Remote image\" title=\"Example\""),
      html.contains("href=\"docs/Guide File.md\" title=\"Guide title\">Reference <strong>link</strong></a>"),
      html.contains("src=\"https://example.com/reference.png\" alt=\"Reference image\""),
      html.contains("window.__moriSourceAnchors"),
      html.contains("article > [data-source-line]"),
      !html.contains("[guide]:"),
      !html.contains("href=\"javascript:"),
      !html.contains("url(fonts/") else {
    fputs("Renderer did not emit expected enhanced Markdown markup.\n", stderr)
    if let range = html.range(of: "example.com/formatted") ?? html.range(of: "docs/Guide") {
        let start = html.index(range.lowerBound, offsetBy: -80, limitedBy: html.startIndex) ?? html.startIndex
        let end = html.index(range.upperBound, offsetBy: 240, limitedBy: html.endIndex) ?? html.endIndex
        fputs(String(html[start..<end]) + "\n", stderr)
    }
    exit(2)
}

final class SmokeDelegate: NSObject, WKNavigationDelegate {
    private var webView: WKWebView!
    private var attempts = 0

    init(html: String) {
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1100), configuration: configuration)
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("if(window.moriRenderAll){window.moriRenderAll()} true") { [weak self] _, error in
            if let error { self?.fail("Enhancement startup failed: \(error)") }
            else { self?.poll() }
        }
    }

    private func poll() {
        attempts += 1
        webView.evaluateJavaScript("window.moriMermaidDone !== false && window.moriMathDone !== false") { [weak self] value, _ in
            guard let self else { return }
            if value as? Bool == true {
                self.verifyDOM()
            } else if self.attempts < 120 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.poll() }
            } else {
                self.fail("Timed out waiting for math and diagram rendering.")
            }
        }
    }

    private func verifyDOM() {
        let script = """
        ({
          math: document.querySelectorAll('.katex').length,
          displays: document.querySelectorAll('.katex-display').length,
          diagrams: document.querySelectorAll('.diagram-canvas svg').length,
          footnotes: document.querySelectorAll('.footnotes li').length,
          headings: document.querySelectorAll('h1').length,
          frontMatter: document.querySelectorAll('.front-matter').length,
          alerts: document.querySelectorAll('.markdown-alert').length,
          blockquotes: document.querySelectorAll('blockquote').length,
          unorderedLists: document.querySelectorAll('ul').length,
          orderedFromThree: document.querySelectorAll('ol[start="3"]').length,
          nestedLists: document.querySelectorAll('ul > li > ol > li > ul').length,
          nestedTasks: document.querySelectorAll('ul > li.task .box.done').length,
          thematicBreaks: document.querySelectorAll('hr').length,
          images: document.querySelectorAll('img[alt="Remote image"]').length,
          tables: document.querySelectorAll('.table-wrap table').length,
          centeredCells: document.querySelectorAll('th[style*="center"],td[style*="center"]').length,
          referenceLinks: document.querySelectorAll('a[href="docs/Guide File.md"],a[href="https://example.com/shortcut"]').length,
          referenceImages: document.querySelectorAll('img[src="https://example.com/reference.png"]').length,
          codeWithBacktick: [...document.querySelectorAll('code')].filter(node => node.textContent.includes('`')).length,
          formattedDirectLinks: document.querySelectorAll('a[href="https://example.com/formatted"] strong').length,
          sourceAnchors: window.moriSourceAnchors().length,
          allSourceNodes: document.querySelectorAll('[data-source-line]').length,
          indexedTopLevelLists: document.querySelectorAll('article > ul[data-source-line],article > ol[data-source-line]').length,
          errors: document.querySelectorAll('.math-error,.mermaid-error').length
        })
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error { self.fail("DOM inspection failed: \(error)"); return }
            guard let result = value as? [String: Any],
                  (result["math"] as? Int ?? 0) >= 2,
                  (result["displays"] as? Int ?? 0) >= 1,
                  (result["diagrams"] as? Int ?? 0) == 1,
                  (result["footnotes"] as? Int ?? 0) == 1,
                  (result["headings"] as? Int ?? 0) == 1,
                  (result["frontMatter"] as? Int ?? 0) == 1,
                  (result["alerts"] as? Int ?? 0) == 1,
                  (result["blockquotes"] as? Int ?? 0) == 1,
                  (result["unorderedLists"] as? Int ?? 0) >= 1,
                  (result["orderedFromThree"] as? Int ?? 0) == 1,
                  (result["nestedLists"] as? Int ?? 0) == 1,
                  (result["nestedTasks"] as? Int ?? 0) == 1,
                  (result["thematicBreaks"] as? Int ?? 0) >= 1,
                  (result["images"] as? Int ?? 0) == 1,
                  (result["tables"] as? Int ?? 0) == 1,
                  (result["centeredCells"] as? Int ?? 0) >= 2,
                  (result["referenceLinks"] as? Int ?? 0) == 3,
                  (result["referenceImages"] as? Int ?? 0) == 1,
                  (result["codeWithBacktick"] as? Int ?? 0) == 1,
                  (result["formattedDirectLinks"] as? Int ?? 0) == 1,
                  (result["sourceAnchors"] as? Int ?? 0) > 0,
                  (result["sourceAnchors"] as? Int ?? 0) < (result["allSourceNodes"] as? Int ?? 0),
                  (result["indexedTopLevelLists"] as? Int ?? 0) >= 3,
                  (result["errors"] as? Int ?? 1) == 0 else {
                self.fail("Unexpected rendered DOM: \(String(describing: value))")
                return
            }
            let pdfConfiguration = WKPDFConfiguration()
            self.webView.createPDF(configuration: pdfConfiguration) { pdfResult in
                guard let data = try? pdfResult.get(), data.count > 10_000,
                      String(data: data.prefix(4), encoding: .ascii) == "%PDF" else {
                    self.fail("Rendered PDF verification failed.")
                    return
                }
                print("renderer-smoke-ok \(result) pdf-bytes=\(data.count)")
                exit(0)
            }
        }
    }

    private func fail(_ message: String) {
        fputs("\(message)\n", stderr)
        exit(3)
    }
}

_ = NSApplication.shared
let delegate = SmokeDelegate(html: html)
withExtendedLifetime(delegate) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
        fputs("Renderer smoke test timed out.\n", stderr)
        exit(4)
    }
    RunLoop.main.run()
}
