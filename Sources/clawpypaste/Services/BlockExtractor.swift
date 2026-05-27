import Foundation

// Walks a list of SessionRecords and emits Blocks ready for the picker.
// Dedupes by Block.id so an identical code fence repeated across turns
// shows up once (most recent turn wins for ordering purposes).
struct BlockExtractor {
    func extract(records: [SessionRecord]) -> [Block] {
        var byId: [String: Block] = [:]
        var turnIndex = 0

        for rec in records {
            switch rec.type {
            case "user":
                ingestUser(record: rec, turnIndex: turnIndex, into: &byId)
            case "assistant":
                ingestAssistant(record: rec, turnIndex: turnIndex, into: &byId)
                turnIndex += 1
            default:
                continue
            }
        }

        // Order: newest turn first, but within a turn keep insertion order.
        return byId.values.sorted { lhs, rhs in
            if lhs.turnIndex != rhs.turnIndex {
                return lhs.turnIndex > rhs.turnIndex
            }
            return kindRank(lhs.kind) < kindRank(rhs.kind)
        }
    }

    // Within a turn, this order decides what shows first.
    private func kindRank(_ k: BlockKind) -> Int {
        switch k {
        case .code: return 0
        case .table: return 1
        case .toolResult: return 2
        case .toolInput: return 3
        case .markdown: return 4
        case .section: return 5
        case .message: return 6
        case .path: return 7
        case .url: return 8
        }
    }

    // MARK: - Markdown / prose detection

    private static let proseLanguages: Set<String> = [
        "markdown", "md", "text", "txt", "plaintext", "plain", "prose", "none",
    ]

    private static let proseFileSuffixes: [String] = [
        ".md", ".markdown", ".mdx", ".txt", ".rst", ".adoc",
    ]

    private func isProseFilePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if Self.proseFileSuffixes.contains(where: { lower.hasSuffix($0) }) {
            return true
        }
        // Bare README / LICENSE / CHANGELOG etc. with no extension.
        let lastComponent = (path as NSString).lastPathComponent.uppercased()
        if ["README", "LICENSE", "CHANGELOG", "NOTICE", "AUTHORS"].contains(lastComponent) {
            return true
        }
        return false
    }

    private func isProseLanguage(_ lang: String?) -> Bool {
        guard let lang = lang?.lowercased(), !lang.isEmpty else { return false }
        return Self.proseLanguages.contains(lang)
    }

    // MARK: - Per-record ingestion

    private func ingestUser(record: SessionRecord, turnIndex: Int, into byId: inout [String: Block]) {
        guard let content = record.message?.content else { return }
        switch content {
        case .text:
            break  // raw user prompts aren't useful to copy back into Claude
        case .parts(let parts):
            for part in parts where part.type == "tool_result" {
                let text = part.content?.asString ?? ""
                guard !text.isEmpty else { continue }
                insert(
                    .make(
                        kind: .toolResult,
                        content: text,
                        title: nil,
                        turnIndex: turnIndex,
                        timestamp: record.timestamp
                    ),
                    into: &byId
                )
            }
        }
    }

    private func ingestAssistant(record: SessionRecord, turnIndex: Int, into byId: inout [String: Block]) {
        guard case .parts(let parts) = record.message?.content else { return }

        for part in parts {
            switch part.type {
            case "text":
                ingestText(part.text ?? "", turnIndex: turnIndex, timestamp: record.timestamp, into: &byId)
            case "tool_use":
                ingestToolUse(part: part, turnIndex: turnIndex, timestamp: record.timestamp, into: &byId)
            default:
                continue  // skip thinking blocks
            }
        }
    }

    private func ingestToolUse(part: SessionRecord.ContentPart, turnIndex: Int, timestamp: Date?, into byId: inout [String: Block]) {
        let toolName = part.name ?? "tool"
        let filePath = part.input?["file_path"]?.stringValue
        let writesProse = filePath.map(isProseFilePath) ?? false

        let interestingFields: [(key: String, kind: BlockKind, language: String?)] = {
            switch toolName {
            case "Bash":     return [("command", .code, "bash")]
            case "Write":    return [("content", writesProse ? .markdown : .code, nil)]
            case "Edit":     return [
                ("new_string", writesProse ? .markdown : .code, nil),
                ("old_string", .toolInput, nil),
            ]
            case "NotebookEdit": return [("new_source", .code, nil)]
            case "WebFetch", "WebSearch": return [("url", .url, nil), ("query", .toolInput, nil), ("prompt", .toolInput, nil)]
            case "Read":     return [("file_path", .path, nil)]
            case "Glob", "Grep": return [("pattern", .toolInput, nil), ("path", .path, nil)]
            default:         return [("content", .toolInput, nil), ("prompt", .toolInput, nil), ("query", .toolInput, nil)]
            }
        }()

        for field in interestingFields {
            guard let value = part.input?[field.key]?.stringValue, !value.isEmpty else { continue }
            insert(
                .make(
                    kind: field.kind,
                    content: value,
                    language: field.language,
                    title: "\(toolName).\(field.key)",
                    turnIndex: turnIndex,
                    timestamp: timestamp
                ),
                into: &byId
            )
            // Markdown content written to disk may contain tables — surface
            // each one as its own .table block so the user can copy it as
            // CSV / TSV without scrolling the whole file.
            if field.kind == .markdown {
                for table in TableParser.extractTables(from: value) {
                    insert(
                        .make(
                            kind: .table,
                            content: table.raw,
                            title: "\(toolName).\(field.key)",
                            turnIndex: turnIndex,
                            timestamp: timestamp
                        ),
                        into: &byId
                    )
                }
            }
        }
    }

    // MARK: - Text scanning

    private func ingestText(_ text: String, turnIndex: Int, timestamp: Date?, into byId: inout [String: Block]) {
        guard !text.isEmpty else { return }

        // Whole assistant message as a fallback block.
        insert(
            .make(
                kind: .message,
                content: text,
                turnIndex: turnIndex,
                timestamp: timestamp
            ),
            into: &byId
        )

        let codeBlocks = extractCodeFences(from: text)
        for fence in codeBlocks {
            let kind: BlockKind = isProseLanguage(fence.language) ? .markdown : .code
            insert(
                .make(
                    kind: kind,
                    content: fence.content,
                    language: fence.language,
                    turnIndex: turnIndex,
                    timestamp: timestamp
                ),
                into: &byId
            )
        }

        // Strip code fences before scanning prose so we don't grab paths/URLs from code.
        let prose = stripFences(from: text)

        // Markdown tables: emit the raw markdown form as a .table block. The
        // re-parse for CSV/TSV happens lazily at copy time via TableParser.parse.
        for table in TableParser.extractTables(from: prose) {
            insert(
                .make(
                    kind: .table,
                    content: table.raw,
                    turnIndex: turnIndex,
                    timestamp: timestamp
                ),
                into: &byId
            )
        }

        for section in extractSections(from: prose) {
            insert(
                .make(
                    kind: .section,
                    content: section.body,
                    title: section.heading,
                    turnIndex: turnIndex,
                    timestamp: timestamp
                ),
                into: &byId
            )
        }

        for path in extractPaths(from: prose) {
            insert(
                .make(kind: .path, content: path, turnIndex: turnIndex, timestamp: timestamp),
                into: &byId
            )
        }

        for url in extractURLs(from: prose) {
            insert(
                .make(kind: .url, content: url, turnIndex: turnIndex, timestamp: timestamp),
                into: &byId
            )
        }
    }

    private func insert(_ block: Block, into byId: inout [String: Block]) {
        guard !block.content.isEmpty else { return }
        // Newer occurrence wins for turn ordering, but we keep the same id.
        if let existing = byId[block.id], existing.turnIndex >= block.turnIndex {
            return
        }
        byId[block.id] = block
    }

    // MARK: - Code fence extraction

    private struct Fence { let language: String?; let content: String }

    private func extractCodeFences(from text: String) -> [Fence] {
        var results: [Fence] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if let lang = fenceOpener(line) {
                var body: [String] = []
                i += 1
                while i < lines.count {
                    if isFenceCloser(lines[i]) { break }
                    body.append(lines[i])
                    i += 1
                }
                results.append(Fence(language: lang, content: body.joined(separator: "\n")))
            }
            i += 1
        }
        return results
    }

    private func fenceOpener(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") else { return nil }
        let after = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        // Treat closing ``` (which has nothing after) as not an opener for our walk;
        // the outer loop alternates open/close, so this is fine.
        return after.isEmpty ? "" : after
    }

    private func isFenceCloser(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    private func stripFences(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var inFence = false
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if !inFence { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Section extraction (markdown headings only)

    private struct Section { let heading: String; let body: String }

    private func extractSections(from text: String) -> [Section] {
        let lines = text.components(separatedBy: "\n")
        var sections: [Section] = []
        var current: (heading: String, body: [String])? = nil
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                if let c = current, !c.body.isEmpty {
                    sections.append(Section(heading: c.heading, body: c.body.joined(separator: "\n")))
                }
                let heading = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                current = (heading, [])
            } else if current != nil {
                current?.body.append(line)
            }
        }
        if let c = current, !c.body.isEmpty {
            sections.append(Section(heading: c.heading, body: c.body.joined(separator: "\n")))
        }
        return sections
    }

    // MARK: - Path & URL extraction

    private static let pathRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_/.-])(?:~|/)[A-Za-z0-9_./-]+(?:\.[A-Za-z0-9]+)?(?::\d+)?"#
    )

    private static let urlRegex = try! NSRegularExpression(
        pattern: #"https?://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+"#
    )

    private func extractPaths(from text: String) -> [String] {
        regexMatches(Self.pathRegex, in: text)
            .filter { $0.count >= 4 }  // skip "/a" noise
            .filter { $0.contains("/") }
    }

    private func extractURLs(from text: String) -> [String] {
        regexMatches(Self.urlRegex, in: text)
    }

    private func regexMatches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var out: [String] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let m = match else { return }
            let s = ns.substring(with: m.range)
            if seen.insert(s).inserted { out.append(s) }
        }
        return out
    }
}
