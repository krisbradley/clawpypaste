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
    private let queue = DispatchQueue(label: "clawpypaste.history", qos: .utility)

    func ensureBuilt() {
        guard !isLoading, lastBuilt == nil else { return }
        rebuild()
    }

    // Rebuilds when the index is missing or more than a couple of minutes
    // old; unchanged files come from the per-file cache, so this is cheap.
    func ensureFresh() {
        guard !isLoading else { return }
        if let built = lastBuilt, Date().timeIntervalSince(built) < 120 { return }
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

    // Files are parsed in parallel; unchanged files (same mtime) reuse their
    // cached blocks, so a rebuild only re-reads sessions that changed.
    private func scan() -> [Block] {
        let files = Self.sessionFiles()
        let cache = perFileCache
        let lock = NSLock()
        var results = [[Block]?](repeating: nil, count: files.count)
        DispatchQueue.concurrentPerform(iterations: files.count) { i in
            let (file, mtime) = files[i]
            let blocks: [Block]?
            if let entry = cache[file], entry.mtime == mtime {
                blocks = entry.blocks
            } else {
                blocks = (try? SessionParser.parse(url: file)).map { BlockExtractor().extract(records: $0) }
            }
            lock.lock(); results[i] = blocks; lock.unlock()
        }

        var allBlocks: [String: Block] = [:]
        for (i, (file, mtime)) in files.enumerated() {
            guard let fileBlocks = results[i] else { continue }
            perFileCache[file] = CacheEntry(mtime: mtime, blocks: fileBlocks)
            // Stamp each block with its source session so the UI can
            // show a session chip in history mode.
            let meta = SessionTitle.meta(url: file, mtime: mtime)
            let ref = SourceSessionRef(url: file, title: meta.title ?? meta.firstPrompt, agentColor: meta.agentColor)
            for var b in fileBlocks where allBlocks[b.id] == nil {
                b.sourceSession = ref
                allBlocks[b.id] = b
            }
        }

        // turnIndex is meaningless across files, so order by kind rank.
        return allBlocks.values.sorted { kindRank($0.kind) < kindRank($1.kind) }
    }

    private static func sessionFiles() -> [(URL, Date)] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: ActiveSession.projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [(URL, Date)] = []
        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let files = try? fm.contentsOfDirectory(
                      at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            else { continue }
            for file in files where file.pathExtension == "jsonl" {
                if let m = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    out.append((file, m))
                }
            }
        }
        return out
    }

    private func kindRank(_ k: BlockKind) -> Int {
        switch k {
        case .code: return 0
        case .table: return 1
        case .toolResult: return 2
        case .toolInput: return 3
        case .markdown: return 4
        case .section: return 5
        case .quote: return 6
        case .message: return 7
        case .path: return 8
        case .url: return 9
        }
    }
}

