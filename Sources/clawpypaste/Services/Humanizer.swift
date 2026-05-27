import Foundation

// Humanizes prose that smells AI-written. Three passes:
//
// 1. Smart punctuation → plain (em/en dashes, curly quotes, ellipsis, NBSP)
// 2. Strip cliché phrases at sentence boundaries (openings, closings, empty
//    transitions, hedges)
// 3. Simplify overly-formal connectives ("However," → "But ", etc.)
//
// Conservative on word choice — never rewords sentences, only deletes filler
// or swaps single connective words. After deletions, recapitalizes the next
// sentence's first letter and collapses double spaces / triple newlines.
enum Humanizer {
    static func humanize(_ text: String) -> String {
        var out = text

        out = swapSmartPunctuation(in: out)

        for phrase in openingCliches {
            out = removeAtParagraphStart(phrase, in: out)
        }
        for phrase in emptyTransitions {
            out = removeAtSentenceStart(phrase, in: out)
        }
        for phrase in hedgePhrases {
            out = removeAtSentenceStart(phrase, in: out)
        }
        for phrase in closingCliches {
            out = removeAtTrailingEnd(phrase, in: out)
        }
        for (formal, plain) in formalTransitions {
            out = replaceAtSentenceStart(formal, with: plain, in: out)
        }

        out = recapitalizeSentenceStarts(in: out)
        out = collapseWhitespace(in: out)

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Shown next to "Copy humanized" — if false, the menu item is hidden so
    // the user isn't offered a no-op transform.
    static func looksAIGenerated(_ text: String) -> Bool {
        if hasSmartPunctuation(text) { return true }
        let lower = text.lowercased()
        for phrase in openingCliches + emptyTransitions + closingCliches + hedgePhrases {
            if lower.contains(phrase.lowercased()) { return true }
        }
        for (formal, _) in formalTransitions {
            if lower.contains(formal.lowercased()) { return true }
        }
        return false
    }

    // Kept for backwards compatibility with earlier call sites.
    static func looksAIPunctuated(_ text: String) -> Bool { hasSmartPunctuation(text) }

    // MARK: - Punctuation pass

    private static func swapSmartPunctuation(in text: String) -> String {
        var out = text
        out = out.replacingOccurrences(of: " — ", with: " - ")
        out = out.replacingOccurrences(of: "—", with: "-")
        out = out.replacingOccurrences(of: " – ", with: " - ")
        out = out.replacingOccurrences(of: "–", with: "-")
        out = out.replacingOccurrences(of: "\u{201C}", with: "\"")
        out = out.replacingOccurrences(of: "\u{201D}", with: "\"")
        out = out.replacingOccurrences(of: "\u{2018}", with: "'")
        out = out.replacingOccurrences(of: "\u{2019}", with: "'")
        out = out.replacingOccurrences(of: "\u{2026}", with: "...")
        out = out.replacingOccurrences(of: "\u{00A0}", with: " ")
        return out
    }

    private static func hasSmartPunctuation(_ text: String) -> Bool {
        text.contains("—")
            || text.contains("–")
            || text.contains("\u{201C}") || text.contains("\u{201D}")
            || text.contains("\u{2018}") || text.contains("\u{2019}")
            || text.contains("\u{2026}")
            || text.contains("\u{00A0}")
    }

    // MARK: - Phrase lists

    // Front-of-message warmup boilerplate.
    private static let openingCliches = [
        "Certainly! ", "Certainly, ",
        "Absolutely! ", "Absolutely, ",
        "Of course! ", "Of course, ",
        "Sure thing! ", "Sure! ",
        "Great question! ", "Great question, ",
        "Great point! ", "Great point, ",
        "Excellent question! ", "Excellent! ",
        "I'd be happy to ", "I'll be happy to ", "I am happy to ", "I'm happy to ",
    ]

    // "It's worth noting that <sentence>" → "<sentence>"
    private static let emptyTransitions = [
        "It's worth noting that ",
        "It is worth noting that ",
        "It's important to note that ",
        "It is important to note that ",
        "It's worth mentioning that ",
        "It's important to understand that ",
        "It is important to understand that ",
        "It's worth pointing out that ",
        "It should be noted that ",
        "Keep in mind that ",
        "Bear in mind that ",
        "Note that ",
        "Please note that ",
        "Worth noting: ",
    ]

    // Mild hedges that just add words.
    private static let hedgePhrases = [
        "Essentially, ",
        "Basically, ",
        "Fundamentally, ",
        "In essence, ",
        "Generally speaking, ",
        "Broadly speaking, ",
    ]

    // Trailing helpdesk-style sign-offs.
    private static let closingCliches = [
        "I hope this helps!", "I hope this helps.",
        "I hope that helps!", "I hope that helps.",
        "Hope this helps!", "Hope this helps.",
        "Hope that helps!", "Hope that helps.",
        "Let me know if you have any questions!", "Let me know if you have any questions.",
        "Let me know if you have questions!", "Let me know if you have questions.",
        "Let me know if you need anything else!", "Let me know if you need anything else.",
        "Let me know if you need any clarification!", "Let me know if you need any clarification.",
        "Feel free to ask!", "Feel free to ask.",
        "Feel free to reach out!", "Feel free to reach out.",
        "Feel free to ask if you have any questions!",
        "Happy to clarify!", "Happy to clarify.",
        "Happy to help!", "Happy to help.",
    ]

    // Overly formal connectives.
    private static let formalTransitions: [(String, String)] = [
        ("However, ", "But "),
        ("Furthermore, ", "Also, "),
        ("Moreover, ", "Also, "),
        ("Additionally, ", "Also, "),
        ("Nevertheless, ", "Still, "),
        ("Nonetheless, ", "Still, "),
    ]

    // MARK: - Regex helpers

    private static func escape(_ s: String) -> String {
        NSRegularExpression.escapedPattern(for: s)
    }

    // Paragraph start = start of text, or after a blank line.
    private static func removeAtParagraphStart(_ phrase: String, in text: String) -> String {
        let pat = "(^|\\n\\n)\(escape(phrase))"
        return text.replacingOccurrences(
            of: pat,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    // Sentence start = start of text, after newline, or after . ! ? + space.
    private static func removeAtSentenceStart(_ phrase: String, in text: String) -> String {
        let pat = "(^|\\n|[.!?] )\(escape(phrase))"
        return text.replacingOccurrences(
            of: pat,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func replaceAtSentenceStart(_ phrase: String, with replacement: String, in text: String) -> String {
        let pat = "(^|\\n|[.!?] )\(escape(phrase))"
        return text.replacingOccurrences(
            of: pat,
            with: "$1\(replacement)",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    // Match trailing phrase even if preceded by a stray space or newline.
    private static func removeAtTrailingEnd(_ phrase: String, in text: String) -> String {
        let pat = "\\s*\(escape(phrase))\\s*$"
        return text.replacingOccurrences(
            of: pat,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    // After stripping a phrase, the next character might now be lowercase
    // mid-sentence. Re-capitalize sentence starts.
    private static func recapitalizeSentenceStarts(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(^|\\n|[.!?] )([a-z])") else {
            return text
        }
        let mutable = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: mutable.length))
        // Iterate in reverse so earlier-range mutations don't shift later ones.
        for m in matches.reversed() {
            guard m.numberOfRanges >= 3 else { continue }
            let charRange = m.range(at: 2)
            guard charRange.location != NSNotFound else { continue }
            let ch = mutable.substring(with: charRange).uppercased()
            mutable.replaceCharacters(in: charRange, with: ch)
        }
        return mutable as String
    }

    private static func collapseWhitespace(in text: String) -> String {
        var out = text
        // Multiple spaces → single (but preserve newlines)
        out = out.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        // Triple-or-more newlines → double
        out = out.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return out
    }
}
