import Foundation
import Combine

// Central state object. Wires together the active-session detector, the file
// watcher, the parser, and the extractor, and publishes the result for the UI.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var blocks: [Block] = []
    @Published private(set) var activePath: String = "—"
    @Published private(set) var activeProject: String = "—"
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var recentSessions: [ActiveSession.Info] = []
    @Published private(set) var manuallyPinnedSession: URL? = nil
    @Published var searchText: String = ""
    @Published var kindFilter: BlockKind? = nil
    @Published var recentlyCopiedId: String? = nil
    @Published var selectedBlockId: String? = nil
    @Published var scope: Scope = .active
    @Published private(set) var pinned: [PinnedBlock] = []

    enum Scope: Equatable {
        case active
        case history
    }

    // Set by AppDelegate to auto-dismiss the popover after a copy / to send
    // text into the previously-focused app.
    var onCopy: (() -> Void)?
    var onInject: ((String) -> Void)?

    func inject(_ block: Block) {
        onInject?(block.content)
    }

    func selectFirstIfNeeded() {
        if selectedBlockId == nil, let first = filteredBlocks.first {
            selectedBlockId = first.id
        }
    }

    func moveSelection(by offset: Int) {
        let blocks = filteredBlocks
        guard !blocks.isEmpty else { return }
        let currentIndex = blocks.firstIndex(where: { $0.id == selectedBlockId }) ?? -1
        let newIndex = max(0, min(blocks.count - 1, currentIndex + offset))
        selectedBlockId = blocks[newIndex].id
    }

    func copySelected() {
        guard let id = selectedBlockId,
              let block = filteredBlocks.first(where: { $0.id == id })
        else { return }
        copy(block)
    }

    private let extractor = BlockExtractor()
    private var watcher: FileWatcher?
    private var rescanTimer: Timer?
    private var debounce: DispatchWorkItem?

    init() {
        pinned = PinStore.load()
        rescan()
        // Re-check which session is active every 3s — handles the case where
        // the user starts a new Claude session in a different project.
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
    }

    func isPinned(_ block: Block) -> Bool {
        pinned.contains { $0.id == block.id }
    }

    func togglePin(_ block: Block) {
        if let idx = pinned.firstIndex(where: { $0.id == block.id }) {
            pinned.remove(at: idx)
        } else {
            pinned.append(PinnedBlock(from: block))
        }
        PinStore.save(pinned)
    }

    deinit {
        rescanTimer?.invalidate()
    }

    // Union of pinned + scoped blocks, with pinned at the top.
    // Filters and search apply to both. Dedupe by id so the same content
    // doesn't show twice when a pinned block is also present.
    var filteredBlocks: [Block] {
        let sourceBlocks = (scope == .history) ? HistoryStore.shared.blocks : blocks
        let pinnedBlocks = pinned.map { $0.asBlock() }
        let pinnedIds = Set(pinnedBlocks.map(\.id))
        let unpinned = sourceBlocks.filter { !pinnedIds.contains($0.id) }
        var result = pinnedBlocks + unpinned
        if let k = kindFilter {
            result = result.filter { $0.kind == k }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter { $0.content.lowercased().contains(q) }
        }
        return result
    }

    func enterHistoryScope() {
        scope = .history
        HistoryStore.shared.ensureBuilt()
    }

    func exitHistoryScope() {
        scope = .active
    }

    func copy(_ block: Block) {
        copy(block, asText: block.content)
    }

    func copy(_ block: Block, asText text: String) {
        Clipboard.copy(text)
        recentlyCopiedId = block.id
        onCopy?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.recentlyCopiedId == block.id { self?.recentlyCopiedId = nil }
        }
    }

    func rescan() {
        let recent = ActiveSession.findRecent(limit: 5)
        recentSessions = recent

        // If the user has pinned a specific session, honor it; otherwise auto.
        let chosen: ActiveSession.Info?
        if let pinned = manuallyPinnedSession,
           let match = recent.first(where: { $0.url == pinned }) {
            chosen = match
        } else {
            chosen = recent.first
        }

        guard let info = chosen else {
            blocks = []
            activePath = "no Claude session found"
            activeProject = "—"
            return
        }
        activePath = info.url.lastPathComponent
        activeProject = friendlyProjectName(info.projectDir)

        if let w = watcher {
            w.updatePath(info.url)
        } else {
            watcher = FileWatcher(url: info.url) { [weak self] in
                self?.scheduleReparse()
            }
        }
        reparse(url: info.url)
    }

    func switchTo(_ info: ActiveSession.Info) {
        manuallyPinnedSession = info.url
        rescan()
    }

    func resumeAuto() {
        manuallyPinnedSession = nil
        rescan()
    }

    // Display name for a session — the user's custom title or Claude's
    // auto-title if available, else the friendly project path. Used in the
    // header label and the recent-sessions dropdown.
    func displayName(for info: ActiveSession.Info) -> String {
        SessionTitle.meta(url: info.url, mtime: info.modifiedAt).title
            ?? friendlyProjectName(info.projectDir)
    }

    func meta(for info: ActiveSession.Info) -> SessionMeta {
        SessionTitle.meta(url: info.url, mtime: info.modifiedAt)
    }

    private var activeInfo: ActiveSession.Info? {
        recentSessions.first(where: { $0.url.lastPathComponent == activePath })
    }

    var activeDisplayName: String {
        guard let info = activeInfo else { return activeProject }
        return displayName(for: info)
    }

    var activeMeta: SessionMeta? {
        guard let info = activeInfo else { return nil }
        return meta(for: info)
    }

    // ~/.claude/projects encodes paths as "-Users-kristopherbradley-foo".
    // Render that back to "~/foo" for readability.
    private func friendlyProjectName(_ encoded: String) -> String {
        let path = encoded.replacingOccurrences(of: "-", with: "/")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func scheduleReparse() {
        // The file watcher fires for every append; debounce to ~150ms.
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let url = self?.watcher?.url else { return }
                self?.reparse(url: url)
            }
        }
        debounce = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func reparse(url: URL) {
        guard let records = try? SessionParser.parse(url: url) else { return }
        let newBlocks = extractor.extract(records: records)
        blocks = newBlocks
        lastUpdate = Date()
    }
}
