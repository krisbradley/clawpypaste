import Foundation

// Parses {{placeholder}} tokens in a block and fills them with user input.
// Placeholders can repeat (same name used in multiple spots) — that's fine,
// each occurrence gets the same value.
enum SnippetEngine {
    private static let pattern = try! NSRegularExpression(pattern: "\\{\\{\\s*([A-Za-z][A-Za-z0-9_]*)\\s*\\}\\}")

    // Returns the unique placeholder names in order of first appearance.
    static func placeholders(in text: String) -> [String] {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var seen = Set<String>()
        var order: [String] = []
        pattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 2 else { return }
            let name = ns.substring(with: m.range(at: 1))
            if seen.insert(name).inserted { order.append(name) }
        }
        return order
    }

    static func fill(template: String, values: [String: String]) -> String {
        let ns = NSMutableString(string: template)
        let range = NSRange(location: 0, length: ns.length)
        let matches = pattern.matches(in: template, range: range)
        for m in matches.reversed() {
            guard m.numberOfRanges >= 2 else { continue }
            let nameRange = m.range(at: 1)
            let name = ns.substring(with: nameRange)
            let value = values[name] ?? ""
            ns.replaceCharacters(in: m.range, with: value)
        }
        return ns as String
    }

    static func hasPlaceholders(_ text: String) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return pattern.firstMatch(in: text, range: range) != nil
    }
}
