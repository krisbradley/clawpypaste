import Foundation

// Finds the active Claude Code session by scanning ~/.claude/projects/*/.jsonl
// and ranking files by their last real conversation activity. File mtime alone
// misleads: Claude Code appends housekeeping records (title, color, mode…) to
// idle sessions when they're reopened, which made an old session look newest.
enum ActiveSession {
    static var projectsRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    struct Info {
        let url: URL
        let projectDir: String        // e.g. "-Users-kristopherbradley"
        let modifiedAt: Date          // file mtime — use as a cache key
        let lastActivity: Date        // last user/assistant message — use for ranking and display
    }

    static func findActive() -> Info? {
        findRecent(limit: 1).first
    }

    static func findRecent(limit: Int) -> [Info] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var all: [Info] = []
        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let modDate = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
                all.append(Info(url: file, projectDir: dir.lastPathComponent, modifiedAt: modDate, lastActivity: modDate))
            }
        }
        return rankByActivity(all.sorted { $0.modifiedAt > $1.modifiedAt }, limit: limit)
    }

    // Activity is never later than mtime, so walking files newest-mtime-first
    // we can stop once the next file's mtime can't beat the current top `limit`.
    private static func rankByActivity(_ byMtime: [Info], limit: Int) -> [Info] {
        var top: [Info] = []
        for info in byMtime {
            if top.count >= limit, let floor = top.last?.lastActivity, info.modifiedAt <= floor { break }
            let activity = LastActivity.date(url: info.url, mtime: info.modifiedAt) ?? info.modifiedAt
            let ranked = Info(url: info.url, projectDir: info.projectDir, modifiedAt: info.modifiedAt, lastActivity: activity)
            top.append(ranked)
            top.sort { $0.lastActivity > $1.lastActivity }
            if top.count > limit { top.removeLast() }
        }
        return top
    }
}

// Timestamp of the last user/assistant record in a session file, read from
// the end of the file backward. Cached by mtime.
enum LastActivity {
    private struct Entry { let mtime: Date; let date: Date? }
    private struct Stamp: Decodable { let type: String; let timestamp: Date? }

    private static var cache: [URL: Entry] = [:]
    private static let lock = NSLock()
    private static let chunkSize = 256 * 1024
    private static let maxScanBytes: UInt64 = 16 * 1024 * 1024

    static func date(url: URL, mtime: Date) -> Date? {
        lock.lock()
        if let e = cache[url], e.mtime == mtime { lock.unlock(); return e.date }
        lock.unlock()
        let found = scanBackward(url)
        lock.lock()
        cache[url] = Entry(mtime: mtime, date: found)
        lock.unlock()
        return found
    }

    private static func scanBackward(_ url: URL) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            guard let date = parseISO(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "bad date"))
            }
            return date
        }

        var end = size
        var carry = Data()   // partial line spanning a chunk boundary
        while end > 0, size - end < maxScanBytes {
            let start = end >= UInt64(chunkSize) ? end - UInt64(chunkSize) : 0
            guard (try? handle.seek(toOffset: start)) != nil,
                  let chunk = try? handle.read(upToCount: Int(end - start)) else { return nil }
            let buffer = chunk + carry
            // Lines fully inside the buffer, newest first. The first piece may
            // be a partial line unless we reached the start of the file.
            var lines = buffer.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            let firstPartial = start > 0 ? lines.removeFirst() : nil
            for line in lines.reversed() where !line.isEmpty {
                if let stamp = try? decoder.decode(Stamp.self, from: Data(line)),
                   stamp.type == "user" || stamp.type == "assistant",
                   let t = stamp.timestamp {
                    return t
                }
            }
            carry = firstPartial.map { Data($0) } ?? Data()
            end = start
        }
        return nil
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
