import Foundation

// Streams newline-delimited JSON from a session.jsonl file.
// Each line is decoded as a SessionRecord; malformed lines are skipped.
struct SessionParser {
    static func parse(url: URL) throws -> [SessionRecord] {
        let data = try Data(contentsOf: url)
        return parse(data: data)
    }

    static func parse(data: Data) -> [SessionRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var records: [SessionRecord] = []
        var start = data.startIndex
        let newline = UInt8(ascii: "\n")

        for i in data.indices {
            if data[i] == newline {
                if start < i {
                    let lineData = data[start..<i]
                    if let rec = try? decoder.decode(SessionRecord.self, from: lineData) {
                        records.append(rec)
                    }
                }
                start = data.index(after: i)
            }
        }
        if start < data.endIndex {
            let lineData = data[start..<data.endIndex]
            if let rec = try? decoder.decode(SessionRecord.self, from: lineData) {
                records.append(rec)
            }
        }
        return records
    }
}
