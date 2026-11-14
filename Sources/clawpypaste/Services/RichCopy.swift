import Foundation

// Decides what a copy puts on the pasteboard. Tables and markdown-bearing
// prose go out as an HTML flavor plus a clean plain-text flavor (TSV for
// tables, stripped prose otherwise). Each paste destination gets HTML it
// actually renders:
//   - Docs:  semantic HTML, rich table cells (Docs, Word, Pages, Notes)
//   - Slack: real table with plain cells, links spelled out as "text (url)"
//            (Slack drops in-cell formatting)
//   - Email: inline-styled HTML (Gmail/Mail strip <style>, so borders,
//            padding, and code fonts must live on each tag)
// A plain click picks the target from the app that was frontmost when the
// popover opened.
enum RichCopy {
    struct Payload {
        let html: String
        let plain: String
    }

    enum Target { case slack, docs, email }

    // Bundle ID of the app that was frontmost when the popover opened —
    // the likely paste destination. Set by AppDelegate.
    static var pasteTargetBundleID: String?

    private static let slackBundleIDs: Set<String> = ["com.tinyspeck.slackmacgap"]
    private static let emailBundleIDs: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac",
        "com.superhuman.electron", "it.bloop.airmail2",
    ]

    static var likelyTarget: Target {
        let id = pasteTargetBundleID ?? ""
        if slackBundleIDs.contains(id) { return .slack }
        if emailBundleIDs.contains(id) { return .email }
        return .docs
    }

    // True when the block has a rich form worth offering (Copy for Slack /
    // Docs / Email, Copy markdown).
    static func hasRichForm(_ block: Block) -> Bool {
        if block.kind == .table { return TableParser.parse(block.content) != nil }
        return block.isProseLike && hasMarkdownMarkers(block.content)
    }

    static func payload(for block: Block, target: Target) -> Payload? {
        if block.kind == .table, let parsed = TableParser.parse(block.content) {
            switch target {
            case .slack: return Payload(html: parsed.toSlackHTML(), plain: parsed.toSlackTSV())
            case .docs:  return Payload(html: parsed.toHTML(), plain: parsed.toTSV())
            case .email: return Payload(html: EmailStyler.inline(parsed.toHTML()), plain: parsed.toTSV())
            }
        }
        if block.isProseLike, hasMarkdownMarkers(block.content) {
            let html = Transformer.markdownToHTML(block.content)
            return Payload(
                html: target == .email ? EmailStyler.inline(html) : html,
                plain: Transformer.stripMarkdown(block.content)
            )
        }
        return nil
    }

    static func defaultPayload(for block: Block) -> Payload? {
        guard Preferences.shared.richDefaultCopy else { return nil }
        return payload(for: block, target: likelyTarget)
    }

    // Several blocks as one clipboard entry, in the given order. Rich blocks
    // contribute their HTML; everything else is escaped into <pre> (code-like)
    // or <p> so the combined HTML pastes cleanly too.
    static func combined(_ blocks: [Block], target: Target) -> Payload {
        var htmlParts: [String] = []
        var plainParts: [String] = []
        for block in blocks {
            if Preferences.shared.richDefaultCopy, let p = payload(for: block, target: target) {
                htmlParts.append(p.html)
                plainParts.append(p.plain)
            } else {
                let escaped = escapeHTML(block.content)
                htmlParts.append(block.isCodeLike ? "<pre><code>\(escaped)</code></pre>" : "<p>\(escaped)</p>")
                plainParts.append(block.content)
            }
        }
        let html = htmlParts.joined(separator: "\n<br>\n")
        return Payload(
            html: target == .email ? EmailStyler.inline(html) : html,
            plain: plainParts.joined(separator: "\n\n")
        )
    }

    // True when the text contains markdown that would render as styling —
    // plain prose with no markup gains nothing from a rich copy.
    static func hasMarkdownMarkers(_ text: String) -> Bool {
        text.contains("**") || text.contains("__") || text.contains("`") || text.contains("[")
            || text.range(of: "(?m)^#{1,6} ", options: .regularExpression) != nil
            || text.range(of: "(?m)^\\s*([-*+]|\\d+\\.) ", options: .regularExpression) != nil
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// Moves styling onto each tag so email clients that strip <style> blocks
// still render bordered tables and monospace code.
enum EmailStyler {
    private static let styles: [(tag: String, style: String)] = [
        ("table", "border-collapse:collapse;margin:8px 0;font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:14px"),
        ("th", "border:1px solid #d0d7de;padding:6px 10px;background:#f6f8fa;text-align:left;font-weight:600"),
        ("td", "border:1px solid #d0d7de;padding:6px 10px;vertical-align:top"),
        ("pre", "background:#f6f8fa;border:1px solid #d0d7de;border-radius:6px;padding:10px;font-family:Menlo,Consolas,monospace;font-size:12px;white-space:pre-wrap"),
        ("code", "font-family:Menlo,Consolas,monospace;font-size:12px;background:#f6f8fa;padding:1px 4px;border-radius:4px"),
        ("blockquote", "border-left:3px solid #d0d7de;margin:8px 0;padding:2px 12px;color:#57606a"),
        ("p", "margin:0 0 10px 0"),
    ]

    static func inline(_ html: String) -> String {
        var out = html
        for (tag, style) in styles {
            out = out.replacingOccurrences(of: "<\(tag)>", with: "<\(tag) style=\"\(style)\">")
        }
        return out
    }
}
