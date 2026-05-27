import Foundation

enum BlockKind: String, CaseIterable, Codable {
    case code         // fenced code from assistant text, or content written to a code file
    case markdown     // prose content: ```md fences, *.md/*.txt files written by tools
    case table        // markdown table; can be re-rendered as TSV / CSV / md on copy
    case toolResult   // output of a tool call
    case toolInput    // input to a tool call (e.g. Bash command)
    case path         // file path mentioned in text
    case url          // URL mentioned in text
    case message      // a whole assistant message
    case section      // a markdown section under a heading

    var label: String {
        switch self {
        case .code:       return "Code"
        case .markdown:   return "Markdown"
        case .table:      return "Table"
        case .toolResult: return "Tool output"
        case .toolInput:  return "Tool input"
        case .path:       return "Path"
        case .url:        return "URL"
        case .message:    return "Message"
        case .section:    return "Section"
        }
    }
}

struct Block: Identifiable, Hashable {
    let id: String                  // content hash + kind, stable across re-parses
    let kind: BlockKind
    let content: String             // text that lands on the clipboard
    let language: String?           // for code blocks: detected lang, e.g. "swift"
    let title: String?              // for sections: the heading; for tools: tool name
    let turnIndex: Int              // sequence position in the session
    let timestamp: Date?

    var preview: String {
        let firstLine = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? content
        return String(firstLine.prefix(120))
    }

    // For code blocks we show more than one line in the row so the user can
    // recognize what they're about to grab.
    func previewLines(_ max: Int) -> String {
        let lines = content.components(separatedBy: "\n")
        return lines.prefix(max).joined(separator: "\n")
    }

    var lineCount: Int {
        content.split(whereSeparator: \.isNewline).count
    }

    var isCodeLike: Bool {
        kind == .code || kind == .toolResult || kind == .toolInput
    }

    var isProseLike: Bool {
        kind == .markdown || kind == .message || kind == .section
    }

    static func make(
        kind: BlockKind,
        content: String,
        language: String? = nil,
        title: String? = nil,
        turnIndex: Int,
        timestamp: Date?
    ) -> Block {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = Self.hash(kind: kind, content: trimmed)
        return Block(
            id: id,
            kind: kind,
            content: trimmed,
            language: language,
            title: title,
            turnIndex: turnIndex,
            timestamp: timestamp
        )
    }

    private static func hash(kind: BlockKind, content: String) -> String {
        var hasher = Hasher()
        hasher.combine(kind)
        hasher.combine(content)
        return String(hasher.finalize(), radix: 16)
    }
}
