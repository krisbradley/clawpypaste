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
        return pins
    }

    static func save(_ pins: [PinnedBlock]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(pins) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
