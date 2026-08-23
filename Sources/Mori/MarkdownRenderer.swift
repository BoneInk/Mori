import Foundation

enum MarkdownRenderer {
    static func document(markdown: String, title: String, theme: EditorTheme) -> String {
        let body = render(markdown)
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title><style>
        :root{\(theme.css)}
        *{box-sizing:border-box}html,body{margin:0;min-height:100%;background:var(--bg);color:var(--fg)}
        body{font:17px/1.72 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;padding:52px 9% 100px;letter-spacing:.005em}
        article{max-width:760px;margin:auto;overflow-wrap:anywhere}h1,h2,h3,h4{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif;line-height:1.25;margin:1.7em 0 .6em;letter-spacing:-.025em}h1{font-size:2.35em;margin-top:.25em}h2{font-size:1.65em;border-bottom:1px solid var(--line);padding-bottom:.3em}h3{font-size:1.3em}p{margin:1em 0}a{color:var(--accent);text-decoration:none;border-bottom:1px solid color-mix(in srgb,var(--accent) 40%,transparent)}blockquote{margin:1.5em 0;padding:.15em 1.25em;border-left:3px solid var(--accent);color:var(--muted)}code{font:85% ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--code);padding:.16em .35em;border-radius:5px}pre{margin:0;background:var(--code);padding:1.1em 1.25em;overflow:auto;line-height:1.55}pre code{padding:0;background:transparent}.code-block{margin:1.5em 0;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:var(--code)}.code-header{display:flex;align-items:center;height:30px;padding:0 12px;border-bottom:1px solid var(--line);font:600 10px/1 -apple-system,BlinkMacSystemFont,sans-serif;letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}.code-dots{display:flex;gap:5px;margin-right:10px}.code-dots i{width:7px;height:7px;border-radius:50%;background:var(--line)}.tok-keyword{color:var(--syn-key);font-weight:600}.tok-string{color:var(--syn-string)}.tok-comment{color:var(--syn-comment);font-style:italic}.tok-number{color:var(--syn-number)}.tok-type{color:var(--syn-type)}.tok-tag{color:var(--syn-tag)}ul,ol{padding-left:1.4em}li{margin:.35em 0}hr{border:0;border-top:1px solid var(--line);margin:2.5em 0}img,video{max-width:100%;height:auto;border-radius:8px}audio{width:100%}details{margin:1.2em 0;padding:.8em 1em;border:1px solid var(--line);border-radius:8px;background:color-mix(in srgb,var(--code) 35%,transparent)}summary{cursor:pointer;font-weight:650}mark{background:color-mix(in srgb,#ffd95a 55%,transparent);color:inherit;padding:.05em .2em;border-radius:3px}kbd{font:80% ui-monospace,SFMono-Regular,Menlo,monospace;padding:.12em .38em;border:1px solid var(--line);border-bottom-width:2px;border-radius:4px;background:var(--code)}figure{margin:1.5em 0}figcaption{margin-top:.45em;color:var(--muted);font-size:.88em;text-align:center}.task{list-style:none;margin-left:-1.35em}.box{display:inline-flex;width:1.05em;height:1.05em;border:1.5px solid var(--muted);border-radius:3px;margin-right:.55em;vertical-align:-.1em;align-items:center;justify-content:center;color:white;font-size:.75em}.done{background:var(--accent);border-color:var(--accent)}
        .table-wrap{max-width:100%;overflow-x:auto;margin:1.6em 0;border:1px solid var(--line);border-radius:10px}table{width:100%;min-width:620px;border-collapse:collapse;font-size:.9em;line-height:1.55}th,td{padding:.72em .85em;border-right:1px solid var(--line);border-bottom:1px solid var(--line);vertical-align:top}th:last-child,td:last-child{border-right:0}tbody tr:last-child td{border-bottom:0}th{background:var(--code);font-weight:650;white-space:nowrap}tbody tr:nth-child(even){background:color-mix(in srgb,var(--code) 45%,transparent)}td a{word-break:break-word}
        </style></head><body><article>\(body)</article><script>
        window.moriCurrentPosition=()=>{const a=[...document.querySelectorAll('[data-source-line]')];if(!a.length)return{line:0,fraction:0};const y=window.scrollY+1;let c=a[0],top=0;for(const e of a){const t=e.getBoundingClientRect().top+window.scrollY;if(t<=y){c=e;top=t}else break}const h=Math.max(1,c.getBoundingClientRect().height);return{line:Number(c.dataset.sourceLine)||0,fraction:Math.max(0,Math.min(1,(y-top)/h))}};
        window.moriScrollToLine=(line,fraction)=>{const a=[...document.querySelectorAll('[data-source-line]')];if(!a.length)return;let c=a[0];for(const e of a){const n=Number(e.dataset.sourceLine)||0;if(n<=line)c=e;else break}const top=c.getBoundingClientRect().top+window.scrollY;window.scrollTo(0,top+Math.max(0,Math.min(1,fraction))*c.getBoundingClientRect().height)};
        </script></body></html>
        """
    }

    static func render(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var html: [String] = []
        var paragraph: [String] = []
        var inCode = false
        var code: [String] = []
        var codeStart = 0
        var codeLanguage = "text"
        var listType: String?
        var paragraphStart: Int?

        func closeParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p data-source-line=\"\(paragraphStart ?? 0)\">\(inline(paragraph.joined(separator: " ")))</p>")
            paragraph.removeAll()
            paragraphStart = nil
        }
        func closeList() {
            guard let type = listType else { return }
            html.append("</\(type)>")
            listType = nil
        }

        var index = 0
        while index < lines.count {
            let sourceLine = index
            let raw = lines[index]
            index += 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !inCode,
               index < lines.count,
               let header = parseTableRow(line),
               let alignments = parseTableDelimiter(lines[index]),
               header.count == alignments.count {
                closeParagraph(); closeList()
                index += 1
                var rows: [[String]] = []
                while index < lines.count,
                      let row = parseTableRow(lines[index]),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    var normalized = Array(row.prefix(header.count))
                    while normalized.count < header.count { normalized.append("") }
                    rows.append(normalized)
                    index += 1
                }
                html.append(renderTable(header: header, alignments: alignments, rows: rows, sourceLine: sourceLine))
                continue
            }
            if line.hasPrefix("```") {
                closeParagraph(); closeList()
                if inCode {
                    html.append(renderCodeBlock(code.joined(separator: "\n"), language: codeLanguage, sourceLine: codeStart))
                    code.removeAll()
                } else {
                    codeStart = sourceLine
                    let info = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = normalizedLanguage(info)
                }
                inCode.toggle(); continue
            }
            if inCode { code.append(raw); continue }
            if line.isEmpty { closeParagraph(); closeList(); continue }

            if isHTMLBlockLine(line) {
                closeParagraph(); closeList()
                html.append(inline(raw, sourceLine: sourceLine))
            } else if let heading = parseHeading(line) {
                closeParagraph(); closeList()
                html.append("<h\(heading.level) data-source-line=\"\(sourceLine)\">\(inline(heading.title))</h\(heading.level)>")
            } else if line == "---" || line == "***" || line == "___" {
                closeParagraph(); closeList(); html.append("<hr data-source-line=\"\(sourceLine)\">")
            } else if line.hasPrefix("> ") {
                closeParagraph(); closeList(); html.append("<blockquote data-source-line=\"\(sourceLine)\">\(inline(String(line.dropFirst(2))))</blockquote>")
            } else if let item = unorderedItem(line) {
                closeParagraph()
                if listType != "ul" { closeList(); html.append("<ul>"); listType = "ul" }
                html.append("<li data-source-line=\"\(sourceLine)\"\(item.task ? " class=\"task\"" : "")>\(item.box)\(inline(item.text))</li>")
            } else if let item = orderedItem(line) {
                closeParagraph()
                if listType != "ol" { closeList(); html.append("<ol>"); listType = "ol" }
                html.append("<li data-source-line=\"\(sourceLine)\">\(inline(item))</li>")
            } else {
                closeList()
                if paragraphStart == nil { paragraphStart = sourceLine }
                paragraph.append(line)
            }
        }
        if inCode { html.append(renderCodeBlock(code.joined(separator: "\n"), language: codeLanguage, sourceLine: codeStart)) }
        closeParagraph(); closeList()
        return html.joined(separator: "\n")
    }

    private enum TableAlignment {
        case leading
        case center
        case trailing

        var css: String {
            switch self {
            case .leading: return "left"
            case .center: return "center"
            case .trailing: return "right"
            }
        }
    }

    private static func parseTableDelimiter(_ line: String) -> [TableAlignment]? {
        guard let cells = parseTableRow(line), !cells.isEmpty else { return nil }
        var result: [TableAlignment] = []
        for cell in cells {
            let value = cell.trimmingCharacters(in: .whitespaces)
            guard value.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil else { return nil }
            if value.hasPrefix(":") && value.hasSuffix(":") {
                result.append(.center)
            } else if value.hasSuffix(":") {
                result.append(.trailing)
            } else {
                result.append(.leading)
            }
        }
        return result
    }

    private static func parseTableRow(_ line: String) -> [String]? {
        var value = line.trimmingCharacters(in: .whitespaces)
        guard value.contains("|") else { return nil }
        if value.first == "|" { value.removeFirst() }
        if value.last == "|" { value.removeLast() }

        var cells: [String] = []
        var current = ""
        var isEscaped = false
        var isInCode = false
        for character in value {
            if isEscaped {
                current.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
                current.append(character)
            } else if character == "`" {
                isInCode.toggle()
                current.append(character)
            } else if character == "|" && !isInCode {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if isEscaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells.count >= 2 ? cells : nil
    }

    private static func renderTable(header: [String], alignments: [TableAlignment], rows: [[String]], sourceLine: Int) -> String {
        let headings = zip(header, alignments).map { cell, alignment in
            "<th style=\"text-align:\(alignment.css)\">\(inline(cell))</th>"
        }.joined()
        let body = rows.enumerated().map { rowIndex, row in
            let cells = zip(row, alignments).map { cell, alignment in
                "<td style=\"text-align:\(alignment.css)\">\(inline(cell))</td>"
            }.joined()
            return "<tr data-source-line=\"\(sourceLine + rowIndex + 2)\">\(cells)</tr>"
        }.joined()
        return "<div class=\"table-wrap\" data-source-line=\"\(sourceLine)\"><table><thead><tr data-source-line=\"\(sourceLine)\">\(headings)</tr></thead><tbody>\(body)</tbody></table></div>"
    }

    private static func renderCodeBlock(_ code: String, language: String, sourceLine: Int) -> String {
        let highlighted = highlight(code, language: language)
        return """
        <div class="code-block" data-source-line="\(sourceLine)">
        <div class="code-header"><span class="code-dots"><i></i><i></i><i></i></span>\(escape(language))</div>
        <pre><code class="language-\(escape(language))">\(highlighted)</code></pre>
        </div>
        """
    }

    private static func normalizedLanguage(_ info: String) -> String {
        var value = info.lowercased().split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "text"
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "{}."))
        let aliases = [
            "js": "javascript", "jsx": "javascript", "mjs": "javascript",
            "ts": "typescript", "tsx": "typescript",
            "py": "python", "rb": "ruby", "kt": "kotlin",
            "sh": "shell", "bash": "shell", "zsh": "shell",
            "yml": "yaml", "html5": "html", "xml": "html",
            "c++": "cpp", "cxx": "cpp", "cs": "csharp",
            "golang": "go", "rs": "rust", "md": "markdown"
        ]
        return aliases[value] ?? (value.isEmpty ? "text" : value)
    }

    private static func highlight(_ code: String, language: String) -> String {
        guard language != "text" && language != "plaintext" else { return escape(code) }

        let keywordSets: [String: String] = [
            "swift": "actor any as async await associatedtype break case catch class continue convenience copy consuming default defer deinit didSet distributed do dynamic each else enum extension fallthrough false fileprivate final for func get guard if import in indirect init inout internal is isolated let macro mutating nil nonisolated nonmutating open operator optional override package precedencegroup private protocol public repeat required rethrows return self Self set some static struct subscript super switch throws true try typealias unowned var weak where while willSet",
            "java": "abstract assert boolean break byte case catch char class const continue default do double else enum extends false final finally float for goto if implements import instanceof int interface long native new null package private protected public record return sealed short static strictfp super switch synchronized this throw throws transient true try var void volatile while yield",
            "kotlin": "as break class continue do else false for fun if in interface is null object package return super this throw true try typealias typeof val var when while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam where actual abstract annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg",
            "javascript": "async await break case catch class const continue debugger default delete do else export extends false finally for from function get if import in instanceof let new null of return set static super switch this throw true try typeof undefined var void while with yield",
            "typescript": "abstract any as asserts async await bigint boolean break case catch class const constructor continue declare default delete do else enum export extends false finally for from function get if implements import in infer instanceof interface is keyof let module namespace never new null number object of private protected public readonly require return set static string super switch symbol this throw true try type typeof undefined unique unknown var void while with yield",
            "python": "and as assert async await break class continue def del elif else except false finally for from global if import in is lambda none nonlocal not or pass raise return true try while with yield match case",
            "go": "break default func interface select case defer go map struct chan else goto package switch const fallthrough if range type continue for import return var true false nil",
            "rust": "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while",
            "c": "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while",
            "cpp": "alignas alignof and and_eq asm atomic_cancel atomic_commit atomic_noexcept auto bitand bitor bool break case catch char class compl concept const consteval constexpr constinit const_cast continue co_await co_return co_yield decltype default delete do double dynamic_cast else enum explicit export extern false float for friend goto if inline int long mutable namespace new noexcept not nullptr operator or private protected public reflexpr register reinterpret_cast requires return short signed sizeof static static_assert static_cast struct switch synchronized template this thread_local throw true try typedef typeid typename union unsigned using virtual void volatile wchar_t while xor",
            "csharp": "abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using virtual void volatile while async await record",
            "sql": "add all alter and any as asc backup between by case check column constraint create database default delete desc distinct drop exec exists foreign from full group having in index inner insert into is join key left like limit not null or order outer primary procedure right rownum select set table top truncate union unique update values view where with",
            "shell": "case do done elif else esac export fi for function if in local readonly return set shift then time trap unset until while",
            "json": "true false null",
            "yaml": "true false null yes no on off",
            "ruby": "alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield",
            "html": "doctype html head body title meta link script style div span main article section nav header footer table thead tbody tr th td ul ol li a img form input button",
            "css": "import media supports keyframes from to important inherit initial unset var calc grid flex block inline none auto relative absolute fixed sticky"
        ]

        let comments: String
        switch language {
        case "python", "ruby", "shell", "yaml": comments = #"#[^\n]*"#
        case "sql": comments = #"--[^\n]*|/\*[\s\S]*?\*/"#
        case "html": comments = #"<!--[\s\S]*?-->"#
        default: comments = #"//[^\n]*|/\*[\s\S]*?\*/"#
        }
        let strings = language == "python"
            ? #"'''[\s\S]*?'''|\"\"\"[\s\S]*?\"\"\"|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'"#
            : #"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#
        let keywordList = keywordSets[language] ?? keywordSets[language == "markdown" ? "html" : language] ?? ""
        let keywords = keywordList.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "|")
        let keywordPattern = keywords.isEmpty ? #"(?!)"# : #"\b(?:\#(keywords))\b"#
        let tagPattern = language == "html" ? #"</?[A-Za-z][^>]*>"# : #"(?!)"#
        let typePattern = ["swift", "java", "kotlin", "typescript", "go", "rust", "cpp", "csharp"].contains(language)
            ? #"\b[A-Z][A-Za-z0-9_]*\b"# : #"(?!)"#
        let pattern = "(?<comment>\(comments))|(?<string>\(strings))|(?<tag>\(tagPattern))|(?<keyword>\(keywordPattern))|(?<number>\\b(?:0x[0-9A-Fa-f]+|\\d+(?:\\.\\d+)?)\\b)|(?<type>\(typePattern))"
        let options: NSRegularExpression.Options = language == "sql" ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return escape(code) }

        let source = code as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var cursor = 0
        var output = ""
        regex.enumerateMatches(in: code, range: fullRange) { match, _, _ in
            guard let match else { return }
            if match.range.location > cursor {
                output += escape(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            let groups = ["comment", "string", "tag", "keyword", "number", "type"]
            let kind = groups.first { match.range(withName: $0).location != NSNotFound } ?? ""
            output += "<span class=\"tok-\(kind)\">\(escape(source.substring(with: match.range)))</span>"
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length {
            output += escape(source.substring(from: cursor))
        }
        return output
    }

    private static func parseHeading(_ line: String) -> (level: Int, title: String)? {
        let count = line.prefix { $0 == "#" }.count
        guard count > 0, count <= 6, line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }

    private static func unorderedItem(_ line: String) -> (text: String, task: Bool, box: String)? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        var value = String(line.dropFirst(2))
        if value.hasPrefix("[x] ") || value.hasPrefix("[X] ") {
            value = String(value.dropFirst(4)); return (value, true, "<span class=\"box done\">✓</span>")
        }
        if value.hasPrefix("[ ] ") {
            value = String(value.dropFirst(4)); return (value, true, "<span class=\"box\"></span>")
        }
        return (value, false, "")
    }

    private static func orderedItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " else { return nil }
        return String(line[line.index(dot, offsetBy: 2)...])
    }

    private static let safeHTMLTags: Set<String> = [
        "a", "abbr", "address", "article", "aside", "audio", "b", "bdi", "bdo", "blockquote", "br",
        "caption", "center", "cite", "code", "col", "colgroup", "data", "dd", "del", "details", "dfn",
        "div", "dl", "dt", "em", "figcaption", "figure", "font", "footer", "h1", "h2", "h3", "h4", "h5", "h6",
        "header", "hr", "i", "img", "ins", "kbd", "li", "main", "mark", "nav", "ol", "p", "picture",
        "pre", "q", "s", "samp", "section", "small", "source", "span", "strong", "sub", "summary", "sup",
        "table", "tbody", "td", "tfoot", "th", "thead", "time", "tr", "u", "ul", "var", "video", "wbr"
    ]

    private static let safeHTMLAttributes: Set<String> = [
        "abbr", "align", "alt", "cite", "class", "colspan", "controls", "datetime", "dir", "download",
        "color", "face", "height", "href", "hreflang", "id", "lang", "loop", "media", "muted", "open", "poster", "preload",
        "rel", "reversed", "rowspan", "scope", "span", "src", "start", "style", "target", "title", "type",
        "size", "value", "width"
    ]

    private static let booleanHTMLAttributes: Set<String> = [
        "controls", "download", "loop", "muted", "open", "reversed"
    ]

    private static func isHTMLBlockLine(_ line: String) -> Bool {
        var value = line.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("<") else { return false }
        if value.hasPrefix("<!--") { return true }
        value.removeFirst()
        if value.hasPrefix("/") { value.removeFirst() }
        value = value.trimmingCharacters(in: .whitespaces)
        let name = value.prefix { $0.isLetter || $0.isNumber }.lowercased()
        return safeHTMLTags.contains(name)
    }

    private static func inline(_ value: String, sourceLine: Int? = nil) -> String {
        let protected = protectHTML(in: value, sourceLine: sourceLine)
        var result = escape(protected.text)
        let replacements: [(String, String)] = [
            (#"!\[([^\]]+)\]\(([^\s\)]+)\)"#, #"<img src="$2" alt="$1">"#),
            (#"\[([^\]]+)\]\(([^\s\)]+)\)"#, #"<a href="$2">$1</a>"#),
            (#"`([^`]+)`"#, #"<code>$1</code>"#),
            (#"\*\*([^*]+)\*\*"#, #"<strong>$1</strong>"#),
            (#"__([^_]+)__"#, #"<strong>$1</strong>"#),
            (#"(?<!\*)\*([^*]+)\*(?!\*)"#, #"<em>$1</em>"#),
            (#"(?<!_)_([^_]+)_(?!_)"#, #"<em>$1</em>"#),
            (#"~~([^~]+)~~"#, #"<del>$1</del>"#)
        ]
        for (pattern, template) in replacements {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        for (index, token) in protected.tokens.enumerated() {
            result = result.replacingOccurrences(of: htmlPlaceholder(index), with: token)
        }
        return result
    }

    private static func protectHTML(in value: String, sourceLine: Int?) -> (text: String, tokens: [String]) {
        let pattern = #"<!--[\s\S]*?-->|</?[A-Za-z][^>]*>|&(?:#[0-9]+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (value, []) }
        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        var output = ""
        var tokens: [String] = []
        var cursor = 0
        var attachedSourceLine = false

        for match in matches {
            if match.range.location > cursor {
                output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let raw = source.substring(with: match.range)
            let sanitized: String?
            if raw.hasPrefix("&") {
                sanitized = raw
            } else if raw.hasPrefix("<!--") {
                sanitized = "<!-- -->"
            } else {
                let line = attachedSourceLine ? nil : sourceLine
                if let tag = sanitizeHTMLTag(raw, sourceLine: line) {
                    sanitized = tag.html
                    if tag.didAttachSourceLine { attachedSourceLine = true }
                } else {
                    sanitized = nil
                }
            }

            if let sanitized {
                output += htmlPlaceholder(tokens.count)
                tokens.append(sanitized)
            } else {
                output += raw
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length { output += source.substring(from: cursor) }
        return (output, tokens)
    }

    private static func sanitizeHTMLTag(_ raw: String, sourceLine: Int?) -> (html: String, didAttachSourceLine: Bool)? {
        var content = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        let isClosing = content.hasPrefix("/")
        if isClosing {
            content.removeFirst()
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let isSelfClosing = content.hasSuffix("/")
        if isSelfClosing { content.removeLast() }
        let name = String(content.prefix { $0.isLetter || $0.isNumber }).lowercased()
        guard safeHTMLTags.contains(name) else { return nil }
        if isClosing { return ("</\(name)>", false) }

        let nameEnd = content.index(content.startIndex, offsetBy: name.count)
        let attributes = String(content[nameEnd...])
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>`]+)))?"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let source = attributes as NSString
        let matches = regex?.matches(in: attributes, range: NSRange(location: 0, length: source.length)) ?? []
        var renderedAttributes: [String] = []
        var didAttachSourceLine = false

        if let sourceLine {
            renderedAttributes.append("data-source-line=\"\(sourceLine)\"")
            didAttachSourceLine = true
        }
        for match in matches {
            let attribute = source.substring(with: match.range(at: 1)).lowercased()
            guard attribute != "data-source-line",
                  safeHTMLAttributes.contains(attribute) || attribute.hasPrefix("aria-") || attribute.hasPrefix("data-") else { continue }
            let valueRanges = [2, 3, 4].map { match.range(at: $0) }
            guard let range = valueRanges.first(where: { $0.location != NSNotFound }) else {
                if booleanHTMLAttributes.contains(attribute) { renderedAttributes.append(attribute) }
                continue
            }
            var attributeValue = source.substring(with: range)
            if ["href", "src", "poster", "cite"].contains(attribute), !isSafeURL(attributeValue, attribute: attribute) { continue }
            if attribute == "style" {
                let lowered = attributeValue.lowercased()
                if ["expression", "javascript:", "url(", "@import", "-webkit-binding"].contains(where: lowered.contains) { continue }
            }
            if attribute == "target", !["_blank", "_self"].contains(attributeValue.lowercased()) {
                attributeValue = "_self"
            }
            renderedAttributes.append("\(attribute)=\"\(escape(attributeValue))\"")
        }

        let suffix = renderedAttributes.isEmpty ? "" : " " + renderedAttributes.joined(separator: " ")
        return ("<\(name)\(suffix)\(isSelfClosing ? " /" : "")>", didAttachSourceLine)
    }

    private static func isSafeURL(_ value: String, attribute: String) -> Bool {
        let url = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if url.hasPrefix("javascript:") || url.hasPrefix("vbscript:") { return false }
        if url.hasPrefix("data:") { return attribute == "src" && url.hasPrefix("data:image/") }
        return true
    }

    private static func htmlPlaceholder(_ index: Int) -> String {
        "\u{E000}MORIHTML\(index)\u{E001}"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
