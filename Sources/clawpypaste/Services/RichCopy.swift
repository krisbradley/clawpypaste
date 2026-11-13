import Foundation

// Decides what a plain click / Return / ⌘N copy puts on the pasteboard.
// With rich default on, tables and markdown-bearing prose go out as an
// HTML flavor (Docs, Word, Notes, Mail render it) plus a clean plain-text
// flavor (TSV for tables, stripped prose otherwise) for Slack and terminals.
// Raw markdown stays one right-click away via "Copy as Markdown".
enum RichCopy {
    struct Payload {
        let html: String
        let plain: String
    }

    static func defaultPayload(for block: Block) -> Payload? {
        guard Preferences.shared.richDefaultCopy else { return nil }
        if block.kind == .table, let parsed = TableParser.parse(block.content) {
            return Payload(html: parsed.toHTML(), plain: parsed.toTSV())
        }
        if block.isProseLike, hasMarkdownMarkers(block.content) {
            return Payload(
                html: Transformer.markdownToHTML(block.content),
                plain: Transformer.stripMarkdown(block.content)
            )
        }
        return nil
    }

    // True when the text contains markdown that would render as styling —
    // plain prose with no markup gains nothing from a rich copy.
    static func hasMarkdownMarkers(_ text: String) -> Bool {
        text.contains("**") || text.contains("__") || text.contains("`") || text.contains("[")
            || text.range(of: "(?m)^#{1,6} ", options: .regularExpression) != nil
            || text.range(of: "(?m)^\\s*([-*+]|\\d+\\.) ", options: .regularExpression) != nil
    }
}
