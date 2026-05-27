import AppKit
import SwiftUI

// Tiny regex-based syntax highlighter. Not a full lexer — just enough to
// make code previews readable at a glance. Highlights strings, numbers,
// comments, and per-language keywords.
enum SyntaxHighlighter {
    static func highlight(_ code: String, language: String?, fontSize: CGFloat = 11) -> AttributedString {
        let base = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        let langKey = normalize(language)
        for rule in rules(for: langKey) {
            apply(rule, to: base, source: code, fontSize: fontSize)
        }
        return AttributedString(base)
    }

    // MARK: - Rule definitions

    private struct Rule {
        let pattern: String
        let color: NSColor
        let bold: Bool
    }

    private static func normalize(_ language: String?) -> String {
        let lower = (language ?? "").lowercased()
        switch lower {
        case "js", "jsx", "javascript": return "javascript"
        case "ts", "tsx", "typescript": return "typescript"
        case "py", "python": return "python"
        case "rb", "ruby": return "ruby"
        case "sh", "shell", "zsh", "bash": return "bash"
        case "yml", "yaml": return "yaml"
        default: return lower
        }
    }

    private static func rules(for language: String) -> [Rule] {
        var rules: [Rule] = []

        // Strings (double and single quoted). Order matters: do strings first
        // so we don't accidentally bold keyword-like substrings inside them.
        rules.append(Rule(pattern: "\"(?:\\\\.|[^\"\\\\\\n])*\"", color: .systemRed, bold: false))
        rules.append(Rule(pattern: "'(?:\\\\.|[^'\\\\\\n])*'", color: .systemRed, bold: false))

        // Numbers
        rules.append(Rule(pattern: "\\b\\d+(?:\\.\\d+)?\\b", color: .systemPurple, bold: false))

        // Comments + keywords per language
        if let comment = commentPattern(for: language) {
            rules.append(Rule(pattern: comment, color: .systemGray, bold: false))
        }
        if let keywords = keywords(for: language) {
            rules.append(Rule(
                pattern: "\\b(?:\(keywords))\\b",
                color: .systemBlue,
                bold: true
            ))
        }
        return rules
    }

    private static func commentPattern(for language: String) -> String? {
        switch language {
        case "swift", "javascript", "typescript", "kotlin", "java", "c", "cpp", "rust", "go", "php":
            return "//[^\\n]*"
        case "python", "ruby", "bash", "yaml", "toml":
            return "#[^\\n]*"
        case "json", "":
            return nil
        default:
            return "(?:#|//)[^\\n]*"
        }
    }

    private static func keywords(for language: String) -> String? {
        switch language {
        case "swift":
            return "func|let|var|if|else|guard|return|struct|class|enum|protocol|extension|import|where|in|for|while|do|try|catch|throw|throws|public|private|internal|fileprivate|open|static|final|self|Self|nil|true|false|init|deinit|switch|case|default|break|continue|as|is|some|any|inout|async|await|actor|defer|repeat|associatedtype|typealias|operator|precedencegroup|@\\w+"
        case "python":
            return "def|class|if|elif|else|for|while|return|import|from|as|try|except|finally|raise|with|in|is|not|and|or|None|True|False|lambda|yield|pass|break|continue|global|nonlocal|async|await|self|cls"
        case "bash":
            return "if|then|else|elif|fi|for|do|done|while|until|case|esac|in|function|return|export|local|readonly|echo|cd|exit|test|source|alias|unset|trap|set"
        case "javascript", "typescript":
            return "function|const|let|var|if|else|return|class|extends|new|this|super|import|export|from|default|async|await|try|catch|finally|throw|for|while|do|switch|case|break|continue|true|false|null|undefined|typeof|instanceof|in|of|interface|type|enum|implements|public|private|protected|readonly|static|abstract"
        case "json":
            return "true|false|null"
        case "yaml":
            return "true|false|null|yes|no|on|off"
        case "rust":
            return "fn|let|mut|if|else|match|return|struct|enum|trait|impl|use|pub|mod|crate|self|Self|super|where|for|while|loop|break|continue|as|in|move|ref|static|const|unsafe|async|await|dyn|true|false"
        case "go":
            return "func|var|const|type|struct|interface|if|else|for|range|return|import|package|map|chan|go|defer|select|switch|case|default|break|continue|fallthrough|true|false|nil"
        default:
            return nil
        }
    }

    // MARK: - Apply

    private static func apply(_ rule: Rule, to attr: NSMutableAttributedString, source: String, fontSize: CGFloat) {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return }
        let range = NSRange(location: 0, length: (source as NSString).length)
        regex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let m = match else { return }
            attr.addAttribute(.foregroundColor, value: rule.color, range: m.range)
            if rule.bold {
                attr.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
                    range: m.range
                )
            }
        }
    }
}
