import Foundation
import Combine

// State for the full-size window's session browser: list of every Claude Code
// session on disk, the currently selected one, and the blocks parsed from it.
// Separate from SessionStore so that browsing history doesn't interfere with
// the menu bar popover's active-session tracking.
@MainActor
final class SessionBrowserStore: ObservableObject {
    @Published private(set) var sessions: [ActiveSession.Info] = []
    @Published var selectedSessionURL: URL? = nil
    @Published private(set) var blocks: [Block] = []
    @Published var search: String = ""
    @Published var blockKindFilter: BlockKind? = nil
    @Published var blockSearch: String = ""

    private let extractor = BlockExtractor()
    private var loadedURL: URL? = nil

    func refresh() {
        sessions = ActiveSession.findRecent(limit: 500)
        if selectedSessionURL == nil, let first = sessions.first {
            select(first.url)
        }
    }

    func select(_ url: URL) {
        selectedSessionURL = url
        if loadedURL == url { return }
        loadedURL = url
        if let records = try? SessionParser.parse(url: url) {
            blocks = extractor.extract(records: records)
        } else {
            blocks = []
        }
    }

    func meta(for info: ActiveSession.Info) -> SessionMeta {
        SessionTitle.meta(url: info.url, mtime: info.modifiedAt)
    }

    func displayName(for info: ActiveSession.Info) -> String {
        let m = SessionTitle.meta(url: info.url, mtime: info.modifiedAt)
        if let title = m.title { return title }
        if let prompt = m.firstPrompt { return prompt }
        return friendlyPath(info.projectDir)
    }

    var filteredSessions: [ActiveSession.Info] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sessions }
        return sessions.filter { info in
            let m = SessionTitle.meta(url: info.url, mtime: info.modifiedAt)
            let title = (m.title ?? "").lowercased()
            let prompt = (m.firstPrompt ?? "").lowercased()
            let cwd = (m.cwd ?? "").lowercased()
            let dir = info.projectDir.lowercased()
            return title.contains(q) || prompt.contains(q) || cwd.contains(q) || dir.contains(q)
        }
    }

    var filteredBlocks: [Block] {
        var result = blocks
        if let k = blockKindFilter {
            result = result.filter { $0.kind == k }
        }
        let q = blockSearch.lowercased().trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter { $0.content.lowercased().contains(q) }
        }
        return result
    }

    func resume() {
        guard let info = sessions.first(where: { $0.url == selectedSessionURL }) else { return }
        let m = SessionTitle.meta(url: info.url, mtime: info.modifiedAt)
        SessionResumer.resume(sessionURL: info.url, cwd: m.cwd)
    }

    private func friendlyPath(_ encoded: String) -> String {
        let path = encoded.replacingOccurrences(of: "-", with: "/")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
