import Foundation

// Produces a linear user → assistant → user view of a session for the
// browser's conversation tab. Cleaner to read than the block list when you
// want context, less useful when you want to grab specific code.
struct ConversationMessage: Identifiable {
    enum Role { case user, assistant }
    let id: String           // record uuid (or synthesized)
    let role: Role
    let text: String         // concatenated text content
    let timestamp: Date?
    let toolCalls: [String]  // tool names used in this message (assistant only)
}

enum ConversationExtractor {
    static func extract(records: [SessionRecord]) -> [ConversationMessage] {
        var messages: [ConversationMessage] = []
        for (i, rec) in records.enumerated() {
            switch rec.type {
            case "user":
                if let msg = makeUserMessage(rec, index: i) { messages.append(msg) }
            case "assistant":
                if let msg = makeAssistantMessage(rec, index: i) { messages.append(msg) }
            default:
                continue
            }
        }
        return messages
    }

    private static func makeUserMessage(_ rec: SessionRecord, index: Int) -> ConversationMessage? {
        guard let content = rec.message?.content else { return nil }
        let text: String
        switch content {
        case .text(let s):
            // Skip system-injected wrappers — same logic as the session-label
            // first-prompt extraction. Bare strings without any real content
            // are dropped.
            text = stripCommandWrappers(s)
        case .parts(let parts):
            // tool_result parts only — these are agent responses, not user
            // input; skip from the conversation view.
            let texts = parts.compactMap { $0.text }
            text = texts.joined(separator: "\n\n")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ConversationMessage(
            id: rec.uuid ?? "u\(index)",
            role: .user,
            text: trimmed,
            timestamp: rec.timestamp,
            toolCalls: []
        )
    }

    private static func makeAssistantMessage(_ rec: SessionRecord, index: Int) -> ConversationMessage? {
        guard case .parts(let parts) = rec.message?.content else { return nil }
        var textPieces: [String] = []
        var tools: [String] = []
        for part in parts {
            if part.type == "text", let t = part.text, !t.isEmpty {
                textPieces.append(t)
            } else if part.type == "tool_use", let name = part.name {
                tools.append(name)
            }
        }
        let text = textPieces.joined(separator: "\n\n")
        if text.isEmpty && tools.isEmpty { return nil }
        return ConversationMessage(
            id: rec.uuid ?? "a\(index)",
            role: .assistant,
            text: text,
            timestamp: rec.timestamp,
            toolCalls: tools
        )
    }

    // Strip <command-*>...</command-*> and similar wrappers (same approach as
    // session-label extraction) so the conversation view shows what the user
    // actually typed.
    private static func stripCommandWrappers(_ content: String) -> String {
        let pattern = "<([a-zA-Z][a-zA-Z0-9-]*)[^>]*>[\\s\\S]*?</\\1>"
        var stripped = content
        var prev = ""
        while prev != stripped {
            prev = stripped
            stripped = stripped.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return stripped.replacingOccurrences(
            of: "^Caveat: [^\\n]+\\n+",
            with: "",
            options: [.regularExpression, .anchored]
        )
    }
}
