import Foundation

// One-off text transforms exposed via the row right-click menu.
// Each transform returns the converted text (or the original if not applicable).
enum Transformer {
    // Strip the most common markdown formatting so the text reads cleanly when
    // pasted into Slack DMs, plain-text email, or anywhere that won't render
    // markdown.
    static func stripMarkdown(_ text: String) -> String {
        var out = text

        // Fenced code blocks: keep the content, drop the fences and language tag.
        out = out.replacingOccurrences(
            of: "```[a-zA-Z0-9_+-]*\\n?([\\s\\S]*?)\\n?```",
            with: "$1",
            options: .regularExpression
        )

        // Inline code: `code` → code
        out = out.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)

        // Bold: **x** or __x__ → x
        out = out.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)

        // Italic: *x* or _x_ → x  (after bold so we don't eat **x**)
        out = out.replacingOccurrences(of: "(?<![*_])\\*([^*\\n]+)\\*(?![*_])", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?<![*_\\w])_([^_\\n]+)_(?![*_\\w])", with: "$1", options: .regularExpression)

        // Strikethrough
        out = out.replacingOccurrences(of: "~~([^~]+)~~", with: "$1", options: .regularExpression)

        // Links: [text](url) → text (url)
        out = out.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
            with: "$1 ($2)",
            options: .regularExpression
        )

        // Headings: drop leading #s
        out = out.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: [.regularExpression, .anchored])
        out = out.replacingOccurrences(of: "\\n#{1,6}\\s+", with: "\n", options: .regularExpression)

        // Block quotes: drop "> " prefix
        out = out.replacingOccurrences(of: "^> ", with: "", options: [.regularExpression, .anchored])
        out = out.replacingOccurrences(of: "\\n> ", with: "\n", options: .regularExpression)

        // Unordered list markers: "- " → "" at line start (keep indent)
        out = out.replacingOccurrences(of: "(^|\\n)( *)[-*+] ", with: "$1$2", options: .regularExpression)

        return out
    }

    // Pretty-print JSON. If the text isn't valid JSON, return the original.
    static func prettyJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
              ),
              let str = String(data: pretty, encoding: .utf8)
        else { return text }
        return str
    }

    // True if the text parses as JSON. Used to gate the "Pretty-print JSON"
    // menu item so it only appears on applicable blocks.
    static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    // Detect Claude Code's "!command" shebang convention: a single line that
    // starts with "!" followed by a letter, slash, dot, or underscore. This
    // catches user-typed bash prompts like "!ls -la" while skipping noise
    // such as "!=", "!!", "! " or "!important".
    static func looksLikeBangCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("!"), trimmed.count > 1 else { return false }
        if trimmed.contains("\n") { return false }
        let second = trimmed[trimmed.index(after: trimmed.startIndex)]
        return second.isLetter || second == "/" || second == "." || second == "_"
    }

    // Strip the leading "!" (and any whitespace right after it) so the
    // command is ready to paste or execute.
    static func stripBang(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("!") else { return text }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    // True for code blocks whose language identifies them as shell scripts,
    // so the "Run in new Terminal" action knows to offer itself.
    static func looksLikeShellLanguage(_ language: String?) -> Bool {
        guard let lang = language?.lowercased(), !lang.isEmpty else { return false }
        return ["bash", "sh", "shell", "zsh", "console", "terminal", "shellscript"].contains(lang)
    }

    // Wrap the text as a fenced code block with the given language.
    static func wrapInFence(_ text: String, language: String? = nil) -> String {
        let tag = language?.trimmingCharacters(in: .whitespaces) ?? ""
        // Avoid double-wrapping if it's already a fence.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") && trimmed.hasSuffix("```") { return text }
        return "```\(tag)\n\(text)\n```"
    }

    // Convert markdown source to HTML that Google Docs, Word, Pages, Notes,
    // and Mail render as styled text when placed on the pasteboard's HTML
    // type. Handles fenced code, headings, lists, blockquotes, paragraphs,
    // and inline bold/italic/code/strikethrough/links.
    static func markdownToHTML(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var html: [String] = []
        var i = 0

        // Open-list tracking so adjacent list items group under one <ul>/<ol>.
        enum ListKind { case ul, ol }
        var openList: ListKind?
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.joined(separator: " ")
            html.append("<p>\(renderInline(joined))</p>")
            paragraph.removeAll()
        }

        func closeList() {
            guard let kind = openList else { return }
            html.append(kind == .ul ? "</ul>" : "</ol>")
            openList = nil
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                flushParagraph()
                closeList()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let inner = lines[i]
                    if inner.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        break
                    }
                    body.append(escapeHTML(inner))
                    i += 1
                }
                let langAttr = lang.isEmpty ? "" : " class=\"language-\(escapeAttr(lang))\""
                html.append("<pre><code\(langAttr)>\(body.joined(separator: "\n"))</code></pre>")
                i += 1
                continue
            }

            // Blank line → paragraph break and close any open list.
            if trimmed.isEmpty {
                flushParagraph()
                closeList()
                i += 1
                continue
            }

            // Headings.
            if let (level, body) = headingMatch(trimmed) {
                flushParagraph()
                closeList()
                html.append("<h\(level)>\(renderInline(body))</h\(level)>")
                i += 1
                continue
            }

            // Blockquote.
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                closeList()
                var body: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("> ") {
                        body.append(String(t.dropFirst(2)))
                    } else if t == ">" {
                        body.append("")
                    } else {
                        break
                    }
                    i += 1
                }
                html.append("<blockquote><p>\(renderInline(body.joined(separator: " ")))</p></blockquote>")
                continue
            }

            // Unordered list.
            if let item = unorderedItem(line) {
                flushParagraph()
                if openList != .ul {
                    closeList()
                    html.append("<ul>")
                    openList = .ul
                }
                html.append("<li>\(renderInline(item))</li>")
                i += 1
                continue
            }

            // Ordered list.
            if let item = orderedItem(line) {
                flushParagraph()
                if openList != .ol {
                    closeList()
                    html.append("<ol>")
                    openList = .ol
                }
                html.append("<li>\(renderInline(item))</li>")
                i += 1
                continue
            }

            // Plain paragraph line.
            closeList()
            paragraph.append(line)
            i += 1
        }

        flushParagraph()
        closeList()

        return html.joined(separator: "\n")
    }

    // MARK: - markdownToHTML helpers

    private static func headingMatch(_ trimmed: String) -> (Int, String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let after = trimmed.dropFirst(hashes)
        guard after.first == " " else { return nil }
        return (hashes, String(after).trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedItem(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " })
        for marker in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(marker) {
                return String(trimmed.dropFirst(marker.count))
            }
        }
        return nil
    }

    private static let orderedRegex = try! NSRegularExpression(pattern: #"^ *\d+\.\s+(.*)$"#)

    private static func orderedItem(_ line: String) -> String? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = orderedRegex.firstMatch(in: line, range: range) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    // Inline rendering — escape first, then apply markdown→tag replacements on
    // already-escaped text so user-supplied < and > never become tags.
    private static func renderInline(_ text: String) -> String {
        var s = escapeHTML(text)

        // Inline code first so its contents don't get re-processed by bold/italic.
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)

        // Links: [text](url) → <a href="url">text</a>
        s = s.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        // Bold (before italic so we don't eat the ** markers).
        s = s.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: "__([^_]+)__", with: "<strong>$1</strong>", options: .regularExpression)

        // Italic.
        s = s.replacingOccurrences(of: "(?<![*_])\\*([^*\\n]+)\\*(?![*_])", with: "<em>$1</em>", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<![*_\\w])_([^_\\n]+)_(?![*_\\w])", with: "<em>$1</em>", options: .regularExpression)

        // Strikethrough.
        s = s.replacingOccurrences(of: "~~([^~]+)~~", with: "<del>$1</del>", options: .regularExpression)

        return s
    }

    private static func escapeHTML(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "&", with: "&amp;")
        s = s.replacingOccurrences(of: "<", with: "&lt;")
        s = s.replacingOccurrences(of: ">", with: "&gt;")
        return s
    }

    private static func escapeAttr(_ text: String) -> String {
        escapeHTML(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
