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

    // Wrap the text as a fenced code block with the given language.
    static func wrapInFence(_ text: String, language: String? = nil) -> String {
        let tag = language?.trimmingCharacters(in: .whitespaces) ?? ""
        // Avoid double-wrapping if it's already a fence.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") && trimmed.hasSuffix("```") { return text }
        return "```\(tag)\n\(text)\n```"
    }
}
