import SwiftUI
import AppKit

// Full-size window: sidebar of every Claude Code session on disk + detail
// pane with the selected session's blocks or conversation. Inspired by csf.
struct SessionBrowserView: View {
    @StateObject private var browser = SessionBrowserStore()
    let store: SessionStore  // shared with the popover so pin/copy still work
    @FocusState private var focusedField: FocusField?

    enum FocusField: Hashable {
        case sessionSearch
        case blockSearch
        case globalSearch
    }

    var body: some View {
        NavigationSplitView {
            sessionList
        } detail: {
            if browser.isGlobalSearching {
                globalSearchDetail
            } else {
                blockDetail
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .navigationTitle("clawpypaste")
        .onAppear { browser.refresh() }
        .toolbar { toolbar }
        .background(keyboardShortcuts)
    }

    // MARK: - Sidebar

    private var sessionList: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                TextField("Search sessions  (/)", text: $browser.search)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .sessionSearch)
                TextField("Search all blocks  (⌘⇧F)", text: $browser.globalSearch)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .globalSearch)
                    .onChange(of: browser.globalSearch) { _ in
                        browser.ensureGlobalIndex()
                    }
            }
            .padding(8)

            Divider()

            // Route List's selection through browser.select(_:) so the right
            // pane actually reloads. The direct $browser.selectedSessionURL
            // binding only mutates the property; it never triggers the
            // blocks/conversation/stats reload.
            List(selection: Binding(
                get: { browser.selectedSessionURL },
                set: { newValue in
                    if let url = newValue { browser.select(url) }
                }
            )) {
                ForEach(browser.groupedSessions) { group in
                    Section(group.title) {
                        ForEach(group.sessions, id: \.url) { info in
                            let meta = browser.meta(for: info)
                            SessionRow(
                                info: info,
                                title: browser.displayName(for: info),
                                color: meta.swiftUIColor,
                                cwd: meta.cwd,
                                summary: meta.awaySummary,
                                buckets: browser.sparkBuckets[info.url]
                            )
                            .tag(info.url)
                            .contextMenu {
                                Button("Resume in iTerm") {
                                    SessionResumer.resume(sessionURL: info.url, cwd: meta.cwd)
                                }
                                Divider()
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([info.url])
                                }
                                Button("Copy session ID") {
                                    let id = info.url.deletingPathExtension().lastPathComponent
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(id, forType: .string)
                                }
                                Button("Export as markdown…") {
                                    browser.select(info.url)
                                    DispatchQueue.main.async { browser.exportMarkdown() }
                                }
                                Divider()
                                Button("Delete…", role: .destructive) {
                                    browser.select(info.url)
                                    DispatchQueue.main.async { browser.deleteCurrent() }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Text("\(browser.filteredSessions.count) of \(browser.sessions.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { browser.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Re-scan sessions")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 320)
    }

    // MARK: - Detail (blocks)

    private var blockDetail: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            modePicker
            Divider()
            if browser.detailMode == .blocks {
                blockListPane
            } else {
                conversationPane
            }
        }
    }

    private var detailHeader: some View {
        let info = browser.sessions.first(where: { $0.url == browser.selectedSessionURL })
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let info = info {
                    let meta = browser.meta(for: info)
                    if let color = meta.swiftUIColor {
                        Circle().fill(color).frame(width: 10, height: 10)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(browser.displayName(for: info))
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        if let cwd = meta.cwd {
                            Text(friendlyPath(cwd))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    statBadges
                } else {
                    Text("Pick a session")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            // Claude's own summary if it wrote one — usually a much better
            // sense of the session than the first prompt alone.
            if let info = info,
               let summary = browser.meta(for: info).awaySummary,
               !summary.isEmpty
            {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statBadges: some View {
        HStack(spacing: 6) {
            statBadge(systemImage: "person.fill", value: browser.stats.userTurns, label: "user")
            statBadge(systemImage: "sparkles", value: browser.stats.assistantTurns, label: "asst")
            statBadge(systemImage: "wrench", value: browser.stats.toolCalls, label: "tools")
            if let dur = browser.stats.durationLabel {
                Text(dur)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private func statBadge(systemImage: String, value: Int, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9))
            Text("\(value)")
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.15))
        .clipShape(Capsule())
        .foregroundStyle(.secondary)
        .help("\(value) \(label) message\(value == 1 ? "" : "s")")
    }

    private var modePicker: some View {
        HStack {
            Picker("", selection: $browser.detailMode) {
                ForEach(SessionBrowserStore.DetailMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)

            Spacer()

            if browser.detailMode == .blocks {
                TextField("Filter blocks  (⌘F)", text: $browser.blockSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .focused($focusedField, equals: .blockSearch)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var blockListPane: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(nil, label: "All")
                    ForEach(BlockKind.allCases, id: \.self) { k in
                        chip(k, label: k.label)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 6)

            Divider()

            if browser.filteredBlocks.isEmpty {
                emptyDetail("No blocks")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(browser.filteredBlocks) { block in
                            BlockRow(
                                block: block,
                                isRecentlyCopied: store.recentlyCopiedId == block.id,
                                isPinned: store.isPinned(block),
                                isSelected: false,
                                onCopy: { store.copy(block) },
                                onCopyAs: { text in store.copy(block, asText: text) },
                                onCopyRich: { html, plain in store.copy(block, html: html, plain: plain) },
                                onTogglePin: { store.togglePin(block) },
                                onInject: { store.inject(block) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func chip(_ kind: BlockKind?, label: String) -> some View {
        let isActive = browser.blockKindFilter == kind
        return Button(action: { browser.blockKindFilter = kind }) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail (conversation)

    private var conversationPane: some View {
        Group {
            if browser.conversation.isEmpty {
                emptyDetail("No messages")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(browser.conversation) { msg in
                            ConversationBubble(message: msg)
                                .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Detail (global search)

    private var globalSearchDetail: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Searching all sessions for ").foregroundColor(.secondary)
                    + Text("\"\(browser.globalSearch)\"").fontWeight(.medium)
                Spacer()
                if HistoryStore.shared.isLoading {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .font(.system(size: 12))

            Divider()

            let results = browser.globalSearchResults
            if results.isEmpty {
                emptyDetail(HistoryStore.shared.isLoading ? "Indexing…" : "No matches")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { block in
                            BlockRow(
                                block: block,
                                isRecentlyCopied: store.recentlyCopiedId == block.id,
                                isPinned: store.isPinned(block),
                                isSelected: false,
                                onCopy: { store.copy(block) },
                                onCopyAs: { text in store.copy(block, asText: text) },
                                onCopyRich: { html, plain in store.copy(block, html: html, plain: plain) },
                                onTogglePin: { store.togglePin(block) },
                                onInject: { store.inject(block) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func emptyDetail(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar + keyboard

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { browser.resume() } label: {
                Label("Resume", systemImage: "play.fill")
            }
            .disabled(browser.selectedSessionURL == nil)
            .help("Open a new iTerm tab and run claude --resume (⌘↩)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { browser.revealInFinder() } label: {
                Label("Finder", systemImage: "folder")
            }
            .disabled(browser.selectedSessionURL == nil)
        }
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("") { browser.moveSelection(by: 1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { browser.moveSelection(by: -1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { browser.moveSelection(by: 10) }.keyboardShortcut(.downArrow, modifiers: [.shift])
            Button("") { browser.moveSelection(by: -10) }.keyboardShortcut(.upArrow, modifiers: [.shift])
            Button("") { browser.resume() }.keyboardShortcut(.return, modifiers: [.command])
            Button("") { browser.deleteCurrent() }.keyboardShortcut("d", modifiers: [.command])
            Button("") { focusedField = .sessionSearch }.keyboardShortcut("/", modifiers: [])
            Button("") { focusedField = .blockSearch }.keyboardShortcut("f", modifiers: [.command])
            Button("") { focusedField = .globalSearch }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("") { browser.detailMode = .blocks }.keyboardShortcut("1", modifiers: [.command])
            Button("") { browser.detailMode = .conversation }.keyboardShortcut("2", modifiers: [.command])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func friendlyPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Sidebar row

private struct SessionRow: View {
    let info: ActiveSession.Info
    let title: String
    let color: Color?
    let cwd: String?
    let summary: String?
    let buckets: [Int]?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let color = color {
                Circle().fill(color).frame(width: 8, height: 8)
                    .padding(.top, 5)
            } else {
                Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let cwd = cwd {
                    Text(friendly(cwd))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let buckets = buckets, !buckets.isEmpty {
                Sparkline(values: buckets)
                    .frame(width: 48, height: 14)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func friendly(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Conversation bubble

private struct ConversationBubble: View {
    let message: ConversationMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                    .font(.system(size: 9))
                Text(message.role == .user ? "User" : "Assistant")
                    .font(.system(size: 10, weight: .semibold))
                if !message.toolCalls.isEmpty {
                    Text("• \(message.toolCalls.joined(separator: ", "))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)

            if !message.text.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        switch seg {
                        case .prose(let text):
                            Text(MarkdownRenderer.render(text))
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                        case .code(let body, let language):
                            VStack(alignment: .leading, spacing: 4) {
                                if let language = language, !language.isEmpty {
                                    Text(language)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                Text(SyntaxHighlighter.highlight(body, language: language))
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .background(Color.black.opacity(0.06))
                                    .cornerRadius(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(10)
                .background(message.role == .user
                            ? Color.accentColor.opacity(0.12)
                            : Color.gray.opacity(0.10))
                .cornerRadius(8)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
    }

    private enum Segment {
        case prose(String)
        case code(body: String, language: String?)
    }

    // Split the (truncated) message body into prose and ```fence``` code
    // blocks so the bubble view can render code with monospace + the same
    // SyntaxHighlighter used by the block list.
    private var segments: [Segment] {
        let raw = String(message.text.prefix(4000))
        let regex = try? NSRegularExpression(pattern: "```([A-Za-z0-9_+-]*)\\n([\\s\\S]*?)```")
        guard let regex = regex else { return [.prose(raw)] }
        let ns = raw as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var result: [Segment] = []
        var cursor = 0
        regex.enumerateMatches(in: raw, range: fullRange) { match, _, _ in
            guard let m = match else { return }
            if m.range.location > cursor {
                let prose = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                let trimmed = prose.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(.prose(prose)) }
            }
            let lang = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2))
            result.append(.code(body: body, language: lang.isEmpty ? nil : lang))
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            let tail = ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
            let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(.prose(tail)) }
        }
        return result.isEmpty ? [.prose(raw)] : result
    }
}

// MARK: - Sparkline

private struct Sparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 0, 1)
            let step = geo.size.width / CGFloat(max(values.count - 1, 1))
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let y = geo.size.height * (1 - CGFloat(v) / CGFloat(maxV))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
        }
    }
}
