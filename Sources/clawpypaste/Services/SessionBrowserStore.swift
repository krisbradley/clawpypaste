import Foundation
import AppKit

@MainActor
final class SessionBrowserStore: ObservableObject {
    enum DetailMode: String, CaseIterable, Identifiable {
        case blocks
        case conversation
        var id: String { rawValue }
        var label: String {
            switch self {
            case .blocks: return "Blocks"
            case .conversation: return "Conversation"
            }
        }
    }

    @Published private(set) var sessions: [ActiveSession.Info] = []
    @Published var selectedSessionURL: URL? = nil
    @Published private(set) var blocks: [Block] = []
    @Published private(set) var conversation: [ConversationMessage] = []
    @Published private(set) var stats: SessionStats = SessionStats()
    @Published var search: String = ""
    @Published var blockKindFilter: BlockKind? = nil
    @Published var blockSearch: String = ""
    @Published var detailMode: DetailMode = .blocks
    @Published var globalSearch: String = ""

    private let extractor = BlockExtractor()
    private var loadedURL: URL? = nil

    func refresh() {
        sessions = ActiveSession.findRecent(limit: 1000)
        if selectedSessionURL == nil, let first = sessions.first {
            select(first.url)
        }
    }

    func select(_ url: URL) {
        selectedSessionURL = url
        guard loadedURL != url else { return }
        loadedURL = url
        if let records = try? SessionParser.parse(url: url) {
            blocks = extractor.extract(records: records)
            conversation = ConversationExtractor.extract(records: records)
            stats = SessionStats.compute(records: records)
        } else {
            blocks = []
            conversation = []
            stats = SessionStats()
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
            let summary = (m.awaySummary ?? "").lowercased()
            return title.contains(q) || prompt.contains(q) || cwd.contains(q) || dir.contains(q) || summary.contains(q)
        }
    }

    // Sessions partitioned into date buckets for sidebar grouping.
    struct DateGroup: Identifiable {
        let title: String
        let sessions: [ActiveSession.Info]
        var id: String { title }
    }

    var groupedSessions: [DateGroup] {
        let now = Date()
        var today: [ActiveSession.Info] = []
        var yesterday: [ActiveSession.Info] = []
        var week: [ActiveSession.Info] = []
        var month: [ActiveSession.Info] = []
        var older: [ActiveSession.Info] = []
        let cal = Calendar.current
        for info in filteredSessions {
            if cal.isDateInToday(info.modifiedAt) { today.append(info) }
            else if cal.isDateInYesterday(info.modifiedAt) { yesterday.append(info) }
            else if now.timeIntervalSince(info.modifiedAt) < 86400 * 7 { week.append(info) }
            else if now.timeIntervalSince(info.modifiedAt) < 86400 * 30 { month.append(info) }
            else { older.append(info) }
        }
        var groups: [DateGroup] = []
        if !today.isEmpty     { groups.append(DateGroup(title: "Today", sessions: today)) }
        if !yesterday.isEmpty { groups.append(DateGroup(title: "Yesterday", sessions: yesterday)) }
        if !week.isEmpty      { groups.append(DateGroup(title: "Last 7 days", sessions: week)) }
        if !month.isEmpty     { groups.append(DateGroup(title: "Last 30 days", sessions: month)) }
        if !older.isEmpty     { groups.append(DateGroup(title: "Older", sessions: older)) }
        return groups
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

    // Global block search across all sessions, via HistoryStore.
    var isGlobalSearching: Bool {
        !globalSearch.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var globalSearchResults: [Block] {
        let q = globalSearch.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return HistoryStore.shared.blocks.filter { $0.content.lowercased().contains(q) }
    }

    func ensureGlobalIndex() {
        HistoryStore.shared.ensureBuilt()
    }

    // MARK: - Actions

    func resume() {
        guard let info = currentInfo() else { return }
        let m = SessionTitle.meta(url: info.url, mtime: info.modifiedAt)
        SessionResumer.resume(sessionURL: info.url, cwd: m.cwd)
    }

    func revealInFinder() {
        guard let info = currentInfo() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([info.url])
    }

    func copySessionID() {
        guard let info = currentInfo() else { return }
        let id = info.url.deletingPathExtension().lastPathComponent
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(id, forType: .string)
    }

    func exportMarkdown() {
        guard let info = currentInfo() else { return }
        guard !conversation.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(displayName(for: info).prefix(50)).md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let text = self.renderMarkdown(for: info)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func deleteCurrent(confirmed: Bool = false) {
        guard let info = currentInfo() else { return }
        if !confirmed {
            let alert = NSAlert()
            alert.messageText = "Delete this session?"
            alert.informativeText = "\(info.url.lastPathComponent) will be removed from disk. This can't be undone."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            let resp = alert.runModal()
            guard resp == .alertFirstButtonReturn else { return }
        }
        try? FileManager.default.removeItem(at: info.url)
        // Drop the deleted session from our list and pick a neighbor.
        let previousIndex = sessions.firstIndex(where: { $0.url == info.url })
        sessions.removeAll(where: { $0.url == info.url })
        if let i = previousIndex, !sessions.isEmpty {
            let next = sessions[min(i, sessions.count - 1)]
            select(next.url)
        } else {
            selectedSessionURL = sessions.first?.url
            if let url = selectedSessionURL { select(url) }
        }
    }

    private func currentInfo() -> ActiveSession.Info? {
        sessions.first(where: { $0.url == selectedSessionURL })
    }

    private func renderMarkdown(for info: ActiveSession.Info) -> String {
        let meta = SessionTitle.meta(url: info.url, mtime: info.modifiedAt)
        var out: [String] = []
        out.append("# \(displayName(for: info))")
        out.append("")
        if let cwd = meta.cwd { out.append("**Project:** `\(cwd)`") }
        out.append("**Session ID:** `\(info.url.deletingPathExtension().lastPathComponent)`")
        out.append("**Last activity:** \(info.modifiedAt)")
        if let summary = meta.awaySummary {
            out.append("")
            out.append("**Summary:** \(summary)")
        }
        out.append("")
        out.append("---")
        out.append("")
        for msg in conversation {
            let header = msg.role == .user ? "## User" : "## Assistant"
            out.append(header)
            out.append("")
            if !msg.text.isEmpty {
                out.append(msg.text)
                out.append("")
            }
            if !msg.toolCalls.isEmpty {
                out.append("*Tools: \(msg.toolCalls.joined(separator: ", "))*")
                out.append("")
            }
        }
        return out.joined(separator: "\n")
    }

    private func friendlyPath(_ encoded: String) -> String {
        let path = encoded.replacingOccurrences(of: "-", with: "/")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Keyboard nav helpers

    func moveSelection(by offset: Int) {
        let list = filteredSessions
        guard !list.isEmpty else { return }
        let currentIdx = list.firstIndex(where: { $0.url == selectedSessionURL }) ?? -1
        let newIdx = max(0, min(list.count - 1, currentIdx + offset))
        select(list[newIdx].url)
    }
}
