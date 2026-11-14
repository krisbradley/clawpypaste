import Foundation

// On-disk store for pinned blocks. Stored as JSON at
// ~/Library/Application Support/clawpypaste/pins.json so pins survive across
// session switches and app restarts.
struct PinnedBlock: Codable, Identifiable, Hashable {
    let id: String
    let kind: BlockKind
    let content: String
    let language: String?
    let title: String?
    let pinnedAt: Date

    init(id: String, kind: BlockKind, content: String, language: String?, title: String?, pinnedAt: Date) {
        self.id = id; self.kind = kind; self.content = content
        self.language = language; self.title = title; self.pinnedAt = pinnedAt
    }

    // Same pin with its id recomputed by the stable hash (migrates pins
    // saved under the old per-launch random ids).
    func rehashed() -> PinnedBlock {
        PinnedBlock(id: Block.hash(kind: kind, content: content), kind: kind, content: content,
                    language: language, title: title, pinnedAt: pinnedAt)
    }

    init(from block: Block) {
        self.id = block.id
        self.kind = block.kind
        self.content = block.content
        self.language = block.language
        self.title = block.title
        self.pinnedAt = Date()
    }

    func asBlock() -> Block {
        Block(
            id: id,
            kind: kind,
            content: content,
            language: language,
            title: title,
            turnIndex: Int.max,  // pinned always sorts to the top
            timestamp: pinnedAt
        )
    }
}

enum PinStore {
    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("clawpypaste", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pins.json")
    }

    static func load() -> [PinnedBlock] {
        guard let data = try? Data(contentsOf: fileURL),
              let pins = try? JSONDecoder().decode([PinnedBlock].self, from: data)
        else { return [] }
        var seen = Set<String>()
        return pins.map { $0.rehashed() }.filter { seen.insert($0.id).inserted }
    }

    static func save(_ pins: [PinnedBlock]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(pins) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
