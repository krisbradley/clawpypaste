import Foundation

// Decodes newline-delimited JSON from a session.jsonl file. Each line is a
// SessionRecord; malformed lines are skipped.
struct SessionParser {
    static func parse(url: URL) throws -> [SessionRecord] {
        let data = try Data(contentsOf: url)
        return parse(data: data)
    }

    // Parses every line, including a final line with no trailing newline.
    static func parse(data: Data) -> [SessionRecord] {
        var (records, consumed) = parseCompleteLines(data)
        if consumed < data.count {
            let tail = data.subdata(in: consumed..<data.count)
            if let rec = try? makeDecoder().decode(SessionRecord.self, from: tail) {
                records.append(rec)
            }
        }
        return records
    }

    // Parses only newline-terminated lines. Returns the records and how many
    // bytes were consumed, so a caller tailing a growing file can resume at
    // a line boundary and leave a half-written last line for next time.
    static func parseCompleteLines(_ data: Data) -> (records: [SessionRecord], consumed: Int) {
        let decoder = makeDecoder()
        var records: [SessionRecord] = []
        var consumed = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var lineStart = 0
            while lineStart < raw.count,
                  let nl = memchr(base + lineStart, Int32(UInt8(ascii: "\n")), raw.count - lineStart) {
                let lineEnd = base.distance(to: nl)
                if lineEnd > lineStart {
                    let line = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base + lineStart),
                                    count: lineEnd - lineStart, deallocator: .none)
                    if let rec = try? decoder.decode(SessionRecord.self, from: line) {
                        records.append(rec)
                    }
                }
                lineStart = lineEnd + 1
                consumed = lineStart
            }
        }
        return (records, consumed)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// Keeps parsed records for recently viewed sessions. Session files are
// append-only, so a refresh only decodes the bytes added since last time
// instead of the whole (often 50–100 MB) file.
final class SessionRecordCache: @unchecked Sendable {
    static let shared = SessionRecordCache()

    private struct Entry {
        var offset: UInt64
        var records: [SessionRecord]
        var lastUsed: Date
    }

    private var entries: [URL: Entry] = [:]
    private let lock = NSLock()
    private let maxEntries = 3

    func records(for url: URL) -> [SessionRecord] {
        lock.lock()
        let previous = entries[url]
        lock.unlock()

        let entry = refreshed(previous, url: url)
        lock.lock()
        entries[url] = entry
        evictIfNeeded()
        lock.unlock()
        return entry.records
    }

    private func refreshed(_ previous: Entry?, url: URL) -> Entry {
        var entry = previous ?? Entry(offset: 0, records: [], lastUsed: Date())
        entry.lastUsed = Date()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return entry }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        // Shrunk means the file was rewritten — start over.
        if size < entry.offset { entry = Entry(offset: 0, records: [], lastUsed: Date()) }
        guard size > entry.offset else { return entry }
        do { try handle.seek(toOffset: entry.offset) } catch { return entry }
        guard let tail = try? handle.readToEnd(), !tail.isEmpty else { return entry }
        let (newRecords, consumed) = SessionParser.parseCompleteLines(tail)
        entry.records.append(contentsOf: newRecords)
        entry.offset += UInt64(consumed)
        return entry
    }

    // Caller holds the lock.
    private func evictIfNeeded() {
        while entries.count > maxEntries,
              let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            entries.removeValue(forKey: oldest)
        }
    }
}
