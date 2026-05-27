import Foundation

enum DebugDump {
    static func run() {
        guard let info = ActiveSession.findActive() else {
            print("no Claude session found under ~/.claude/projects/")
            return
        }
        print("active session: \(info.url.path)")
        print("  project: \(info.projectDir)")
        print("  modified: \(info.modifiedAt)")

        guard let records = try? SessionParser.parse(url: info.url) else {
            print("failed to parse")
            return
        }
        print("records: \(records.count)")

        let blocks = BlockExtractor().extract(records: records)
        print("blocks: \(blocks.count)")

        var byKind: [BlockKind: Int] = [:]
        for b in blocks { byKind[b.kind, default: 0] += 1 }
        for k in BlockKind.allCases {
            print("  \(k.rawValue): \(byKind[k] ?? 0)")
        }

        print("\n--- first 5 blocks (newest first) ---")
        for b in blocks.prefix(5) {
            let lang = b.language.map { " [\($0)]" } ?? ""
            let title = b.title.map { " — \($0)" } ?? ""
            print("\n[\(b.kind.rawValue)\(lang)\(title)] (\(b.lineCount) lines, turn \(b.turnIndex))")
            print(b.preview)
        }
    }
}
