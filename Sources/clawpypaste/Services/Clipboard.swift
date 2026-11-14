import AppKit

enum Clipboard {
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // Writes both HTML and plain-text representations so apps can pick the
    // richest one they support. Google Docs, Word, Pages, Notes, and Mail
    // read the HTML lane and render formatted; terminals and code editors
    // fall through to the plain-text fallback.
    static func copyRich(html: String, plain: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(withCharset(html), forType: .html)
        pb.setString(plain, forType: .string)
    }

    // Declare UTF-8 explicitly. Without it, Slack (Chromium) misreads
    // non-ASCII characters like → ⌘ ’ in pasted HTML and abandons building a
    // table, flattening it to text instead.
    static func withCharset(_ html: String) -> String {
        html.hasPrefix("<meta charset") ? html : "<meta charset=\"utf-8\">" + html
    }
}
