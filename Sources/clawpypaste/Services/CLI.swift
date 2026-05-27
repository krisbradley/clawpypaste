import Foundation
import AppKit

// Headless CLI for shell scripting. Invoked when the binary is launched with
// a subcommand argument. None of these touch the GUI runtime; they parse the
// active session and write to stdout.
//
//   clawpypaste last [kind]         — print the most recent block (optionally of a kind) to stdout
//   clawpypaste search <query>      — list blocks containing the query (id, kind, first line)
//   clawpypaste paste <id>          — copy the block with that id to the system clipboard
//   clawpypaste list [kind]         — list all blocks (id, kind, first line)
//   clawpypaste kinds               — list valid kind names
//   clawpypaste dump                — same as the --dump diagnostic
//
// All output is plain text; one record per line for `search` and `list`.
enum CLI {
    static func runIfPresent() -> Bool {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else { return false }
        switch cmd {
        case "last":   runLast(kind: args.dropFirst().first); return true
        case "search": runSearch(query: args.dropFirst().joined(separator: " ")); return true
        case "paste":  runPaste(id: args.dropFirst().first ?? ""); return true
        case "list":   runList(kind: args.dropFirst().first); return true
        case "kinds":  runKinds(); return true
        case "dump":   DebugDump.run(); return true
        case "-h", "--help":
            printHelp()
            return true
        default:
            return false
        }
    }

    // MARK: - Commands

    private static func runLast(kind: String?) {
        let blocks = filteredBlocks(kind: kind)
        guard let first = blocks.first else { exit(1) }
        print(first.content)
    }

    private static func runSearch(query: String) {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let blocks = loadActiveBlocks()
        let matches = blocks.filter { $0.content.lowercased().contains(q) }
        for b in matches {
            printRecord(b)
        }
    }

    private static func runPaste(id: String) {
        guard let block = loadActiveBlocks().first(where: { $0.id == id }) else {
            FileHandle.standardError.write("no block with id \(id)\n".data(using: .utf8)!)
            exit(2)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(block.content, forType: .string)
        FileHandle.standardError.write("copied \(block.kind.rawValue) (\(block.lineCount) lines)\n".data(using: .utf8)!)
    }

    private static func runList(kind: String?) {
        let blocks = filteredBlocks(kind: kind)
        for b in blocks {
            printRecord(b)
        }
    }

    private static func runKinds() {
        for k in BlockKind.allCases {
            print("\(k.rawValue)\t\(k.label)")
        }
    }

    // MARK: - Helpers

    private static func filteredBlocks(kind: String?) -> [Block] {
        let blocks = loadActiveBlocks()
        guard let kindRaw = kind, let kind = BlockKind(rawValue: kindRaw) else {
            return blocks
        }
        return blocks.filter { $0.kind == kind }
    }

    private static func loadActiveBlocks() -> [Block] {
        guard let info = ActiveSession.findActive(),
              let records = try? SessionParser.parse(url: info.url)
        else { return [] }
        return BlockExtractor().extract(records: records)
    }

    private static func printRecord(_ b: Block) {
        // id, kind, line count, first-line preview — tab separated
        let first = b.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let preview = String(first.prefix(120))
        print("\(b.id)\t\(b.kind.rawValue)\t\(b.lineCount)L\t\(preview)")
    }

    private static func printHelp() {
        print("""
        clawpypaste — block picker for Claude Code

        GUI:
          clawpypaste                  Launch the menu bar app

        CLI (headless):
          clawpypaste last [kind]      Print the most recent block to stdout
          clawpypaste search <query>   List blocks containing the query
          clawpypaste list [kind]      List all blocks
          clawpypaste paste <id>       Copy a specific block to the clipboard
          clawpypaste kinds            List valid kind names
          clawpypaste dump             Print parser summary

        Maintenance:
          clawpypaste --enable-login   Register as a Login Item
          clawpypaste --disable-login  Unregister
        """)
    }
}
