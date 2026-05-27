import Foundation
import AppKit

// Renders markdown for prose-like blocks. Uses SwiftUI's built-in
// AttributedString(markdown:) for inline syntax (**bold**, *italic*, `code`,
// [links], ~~strike~~). Block-level syntax (headings, list bullets, fenced
// code) gets a light pass so headings render bolder and list markers stay
// visible — AttributedString's parser doesn't render those itself.
enum MarkdownRenderer {
    static func render(_ raw: String) -> AttributedString {
        let lines = raw.components(separatedBy: "\n")
        var out = AttributedString("")

        for (i, line) in lines.enumerated() {
            out.append(renderLine(line))
            if i < lines.count - 1 {
                out.append(AttributedString("\n"))
            }
        }
        return out
    }

    private static func renderLine(_ line: String) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Headings: bold + slightly larger
        if trimmed.hasPrefix("#") {
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            let body = trimmed
                .drop(while: { $0 == "#" })
                .trimmingCharacters(in: .whitespaces)
            var attr = inlineMarkdown(String(body))
            let size: CGFloat = max(12, 16 - CGFloat(hashes - 1) * 1.5)
            attr.font = .system(size: size, weight: .bold)
            return attr
        }

        // Unordered list: render the bullet as a visible glyph and parse the rest inline.
        if let listMatch = listPrefix(line) {
            var bullet = AttributedString("•  ")
            bullet.foregroundColor = NSColor.secondaryLabelColor
            let rest = inlineMarkdown(listMatch.remainder)
            let indent = AttributedString(String(repeating: " ", count: listMatch.indent))
            var combined = indent
            combined.append(bullet)
            combined.append(rest)
            return combined
        }

        // Numbered list: keep the number, parse the rest inline.
        if let numMatch = numberedPrefix(line) {
            let prefix = AttributedString("\(numMatch.number).  ")
            let indent = AttributedString(String(repeating: " ", count: numMatch.indent))
            var combined = indent
            combined.append(prefix)
            combined.append(inlineMarkdown(numMatch.remainder))
            return combined
        }

        // Block quote: prefix with a vertical bar and dim it.
        if trimmed.hasPrefix("> ") {
            let body = String(trimmed.dropFirst(2))
            var bar = AttributedString("│ ")
            bar.foregroundColor = NSColor.tertiaryLabelColor
            var rest = inlineMarkdown(body)
            rest.foregroundColor = NSColor.secondaryLabelColor
            bar.append(rest)
            return bar
        }

        return inlineMarkdown(line)
    }

    private static func inlineMarkdown(_ s: String) -> AttributedString {
        // AttributedString's markdown parser only handles inline syntax. We
        // want to keep blank lines so paragraph spacing reads correctly.
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attr = try? AttributedString(markdown: s, options: options) {
            return attr
        }
        return AttributedString(s)
    }

    // MARK: - List detection

    private struct ListMatch {
        let indent: Int
        let remainder: String
    }

    private static func listPrefix(_ line: String) -> ListMatch? {
        let indent = line.prefix(while: { $0 == " " }).count
        let trimmed = line.drop(while: { $0 == " " })
        for marker in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(marker) {
                return ListMatch(indent: indent, remainder: String(trimmed.dropFirst(marker.count)))
            }
        }
        return nil
    }

    private struct NumberedMatch {
        let indent: Int
        let number: Int
        let remainder: String
    }

    private static let numberedRegex = try! NSRegularExpression(pattern: #"^( *)(\d+)\.\s+(.*)$"#)

    private static func numberedPrefix(_ line: String) -> NumberedMatch? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = numberedRegex.firstMatch(in: line, range: range) else { return nil }
        let indent = ns.substring(with: m.range(at: 1)).count
        let number = Int(ns.substring(with: m.range(at: 2))) ?? 1
        let remainder = ns.substring(with: m.range(at: 3))
        return NumberedMatch(indent: indent, number: number, remainder: remainder)
    }
}
