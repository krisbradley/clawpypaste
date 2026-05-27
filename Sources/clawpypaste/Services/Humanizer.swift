import Foundation

// "Humanize" prose by stripping the punctuation tells that out AI-written
// text. Conservative by default — only swaps punctuation, never rewords.
enum Humanizer {
    static func humanize(_ text: String) -> String {
        var out = text

        // Em dash and en dash → space-dash-space (preserves spacing) or just dash
        // depending on context. Default: replace with " - " so the sentence
        // still reads naturally.
        out = out.replacingOccurrences(of: " — ", with: " - ")
        out = out.replacingOccurrences(of: "—", with: "-")
        out = out.replacingOccurrences(of: " – ", with: " - ")
        out = out.replacingOccurrences(of: "–", with: "-")

        // Smart double quotes → straight
        out = out.replacingOccurrences(of: "\u{201C}", with: "\"")
        out = out.replacingOccurrences(of: "\u{201D}", with: "\"")
        // Smart single quotes / apostrophes → straight
        out = out.replacingOccurrences(of: "\u{2018}", with: "'")
        out = out.replacingOccurrences(of: "\u{2019}", with: "'")

        // Ellipsis → three dots
        out = out.replacingOccurrences(of: "\u{2026}", with: "...")

        // Non-breaking space → regular space
        out = out.replacingOccurrences(of: "\u{00A0}", with: " ")

        return out
    }

    // Quick check so we only show the humanize option on blocks that
    // actually contain the punctuation we'd transform.
    static func looksAIPunctuated(_ text: String) -> Bool {
        text.contains("—")
            || text.contains("–")
            || text.contains("\u{201C}") || text.contains("\u{201D}")
            || text.contains("\u{2018}") || text.contains("\u{2019}")
            || text.contains("\u{2026}")
    }
}
