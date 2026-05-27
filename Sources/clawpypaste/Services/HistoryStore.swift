import Foundation

// Lazy across-all-sessions index. Walks every jsonl file under
// ~/.claude/projects, parses each, extracts blocks, dedupes by id, and caches
// per file by mtime so subsequent scans only re-read changed sessions.
//
// Building the first index can take a few seconds on machines with many large
// session files; the loader uses a background queue and publishes `isLoading`
// so the UI can show a spinner.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var blocks: [Block] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastBuilt: Date?

    private struct CacheEntry {
        let mtime: Date
        let blocks: [Block]
    }

    private var perFileCache: [URL: CacheEntry] = [:]
    private let extractor = BlockExtractor()
    private let queue = DispatchQueue(label: "clawpypaste.history", qos: .utility)

    func ensureBuilt() {
        guard !isLoading, lastBuilt == nil else { return }
        rebuild()
    }

    func rebuild() {
        DispatchQueue.main.async { self.isLoading = true }
        queue.async { [weak self] in
            guard let self = self else { return }
            let result = self.scan()
            DispatchQueue.main.async {
                self.blocks = result
                self.isLoading = false
                self.lastBuilt = Date()
            }
        }
    }

    private func scan() -> [Block] {
        let fm = FileManager.default
        let projectsRoot = ActiveSession.projectsRoot
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var allBlocks: [String: Block] = [:]

        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let mtime = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
                let fileBlocks: [Block]
                if let entry = perFileCache[file], entry.mtime == mtime {
                    fileBlocks = entry.blocks
                } else if let records = try? SessionParser.parse(url: file) {
                    fileBlocks = extractor.extract(records: records)
                    perFileCache[file] = CacheEntry(mtime: mtime, blocks: fileBlocks)
                } else {
                    continue
                }
                for b in fileBlocks where allBlocks[b.id] == nil {
                    allBlocks[b.id] = b
                }
            }
        }

        // Order: code-like first (turnIndex used for active session is meaningless
        // across files), so just sort by content kind rank within each id.
        return allBlocks.values.sorted { lhs, rhs in
            kindRank(lhs.kind) < kindRank(rhs.kind)
        }
    }

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
}
