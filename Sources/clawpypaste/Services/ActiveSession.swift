import Foundation

// Finds the active Claude Code session by scanning ~/.claude/projects/*/.jsonl
// and picking the file with the most recent modification time. That's the file
// being written to right now by the running session.
enum ActiveSession {
    static var projectsRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    struct Info {
        let url: URL
        let projectDir: String        // e.g. "-Users-kristopherbradley"
        let modifiedAt: Date
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
                all.append(Info(url: file, projectDir: dir.lastPathComponent, modifiedAt: modDate))
            }
        }
        return Array(all.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(limit))
    }
}
