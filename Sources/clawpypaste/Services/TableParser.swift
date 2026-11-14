import Foundation

// Parses markdown tables and re-renders them as TSV, CSV, or the original
// markdown. A "table" is a block of lines like:
//
//   | col1 | col2 | col3 |
//   |------|------|------|
//   | a    | b    | c    |
//   | d    | e    | f    |
//
// The separator line (dashes, optionally with `:` for alignment) is what we
// use to confirm a `|`-line is really a table header.
struct ParsedTable {
    let header: [String]
    let rows: [[String]]

    func toMarkdown() -> String {
        var out: [String] = []
        out.append("| " + header.joined(separator: " | ") + " |")
        out.append("|" + Array(repeating: "---", count: header.count).joined(separator: "|") + "|")
        for row in rows {
            // Pad/truncate to header count for safety.
            var padded = row
            while padded.count < header.count { padded.append("") }
            out.append("| " + padded.prefix(header.count).joined(separator: " | ") + " |")
        }
        return out.joined(separator: "\n")
    }

    // Cells are rendered through the inline-markdown renderer so **bold**,
    // `code`, and [links](url) become real formatting in Docs/Word/Notes.
    func toHTML() -> String {
        var out = "<table><thead><tr>"
        for h in header { out += "<th>\(Transformer.renderInline(h))</th>" }
        out += "</tr></thead><tbody>"
        for row in rows {
            var padded = row
            while padded.count < header.count { padded.append("") }
            out += "<tr>"
            for cell in padded.prefix(header.count) { out += "<td>\(Transformer.renderInline(cell))</td>" }
            out += "</tr>"
        }
        out += "</tbody></table>"
        return out
    }

    // Slack builds a real table from pasted HTML but drops all in-cell
    // formatting (tags, styles, links alike). So cells go in as plain text,
    // with links spelled out as "text (url)" so the URL isn't lost.
    func toSlackHTML() -> String {
        func cell(_ s: String) -> String {
            slackSafe(plain(s)).replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        var out = "<table><thead><tr>"
        for h in header { out += "<th>\(cell(h))</th>" }
        out += "</tr></thead><tbody>"
        for row in rows {
            var padded = row
            while padded.count < header.count { padded.append("") }
            out += "<tr>"
            for c in padded.prefix(header.count) { out += "<td>\(cell(c))</td>" }
            out += "</tr>"
        }
        out += "</tbody></table>"
        return out
    }

    // TSV for the Slack payload's plain-text flavor. Slack inspects this
    // too: a "#" in it makes Slack treat the paste as markdown text and skip
    // building the table, so it gets the same "#" treatment as the HTML.
    func toSlackTSV() -> String {
        var out: [String] = []
        out.append(header.map { tabSafe(slackSafe($0)) }.joined(separator: "\t"))
        for row in rows {
            out.append(row.map { tabSafe(slackSafe($0)) }.joined(separator: "\t"))
        }
        return out.joined(separator: "\n")
    }

    func toTSV() -> String {
        var out: [String] = []
        out.append(header.map(tabSafe).joined(separator: "\t"))
        for row in rows {
            out.append(row.map(tabSafe).joined(separator: "\t"))
        }
        return out.joined(separator: "\n")
    }

    func toCSV() -> String {
        var out: [String] = []
        out.append(header.map(csvEscape).joined(separator: ","))
        for row in rows {
            out.append(row.map(csvEscape).joined(separator: ","))
        }
        return out.joined(separator: "\n")
    }

    // Plain-text exports drop inline markdown so Slack/Sheets get clean
    // values instead of literal asterisks and backticks.
    private func plain(_ cell: String) -> String {
        Transformer.stripMarkdown(cell).replacingOccurrences(of: "<br>", with: " ")
    }

    // Slack refuses to build a table when a cell contains "#" (it flattens
    // the paste to text; a zero-width-space prefix doesn't fool it). A bare
    // "#" header becomes "No."; other "#" become the look-alike full-width ＃.
    private func slackSafe(_ cell: String) -> String {
        if cell.trimmingCharacters(in: .whitespaces) == "#" { return "No." }
        return cell.replacingOccurrences(of: "#", with: "\u{FF03}")
    }

    private func tabSafe(_ cell: String) -> String {
        plain(cell).replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func csvEscape(_ raw: String) -> String {
        let cell = plain(raw)
        if cell.contains(",") || cell.contains("\"") || cell.contains("\n") {
            return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return cell
    }
}

enum TableParser {
    // Find all markdown tables in `text`. Returns each table as the original
    // raw markdown so it can survive round-tripping, plus a parsed form.
    static func extractTables(from text: String) -> [(raw: String, parsed: ParsedTable)] {
        let lines = text.components(separatedBy: "\n")
        var out: [(String, ParsedTable)] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            // Need at least: header line + separator line + 1 data line.
            if i + 2 < lines.count,
               isPipeRow(line),
               isSeparatorRow(lines[i + 1]),
               isPipeRow(lines[i + 2])
            {
                let headerCells = splitPipeRow(line)
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count, isPipeRow(lines[j]) {
                    rows.append(splitPipeRow(lines[j]))
                    j += 1
                }
                if !rows.isEmpty {
                    let rawSlice = lines[i..<j].joined(separator: "\n")
                    let parsed = ParsedTable(header: headerCells, rows: rows)
                    out.append((rawSlice, parsed))
                }
                i = j
            } else {
                i += 1
            }
        }
        return out
    }

    private static func isPipeRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count >= 3
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return false }
        let body = trimmed.dropFirst().dropLast()
        // Each cell must be only dashes, colons, and spaces, and contain at
        // least one dash.
        let cells = body.split(separator: "|", omittingEmptySubsequences: false)
        for cell in cells {
            let s = cell.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { return false }
            if !s.allSatisfy({ $0 == "-" || $0 == ":" }) { return false }
            if !s.contains("-") { return false }
        }
        return cells.count >= 1
    }

    private static func splitPipeRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let body = trimmed.dropFirst().dropLast()  // strip leading/trailing |
        return body.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // Re-parse a raw table block back into ParsedTable (used by Block.parsed
    // since we don't want to store the heavyweight parsed form in every
    // Block instance — only re-parse on demand at copy time).
    static func parse(_ raw: String) -> ParsedTable? {
        let lines = raw.components(separatedBy: "\n")
        guard lines.count >= 3,
              isPipeRow(lines[0]),
              isSeparatorRow(lines[1])
        else { return nil }
        let header = splitPipeRow(lines[0])
        var rows: [[String]] = []
        for line in lines.dropFirst(2) {
            guard isPipeRow(line) else { break }
            rows.append(splitPipeRow(line))
        }
        guard !rows.isEmpty else { return nil }
        return ParsedTable(header: header, rows: rows)
    }
}
