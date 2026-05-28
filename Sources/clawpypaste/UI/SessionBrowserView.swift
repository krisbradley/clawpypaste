import SwiftUI

// Full-size window: sidebar of every Claude Code session on disk + detail
// pane with the selected session's blocks. Drop-in replacement for the
// old detached MainView so the bigger window is now a session manager too.
struct SessionBrowserView: View {
    @StateObject private var browser = SessionBrowserStore()
    let store: SessionStore  // shared with the popover so pin/copy still work

    var body: some View {
        NavigationSplitView {
            sessionList
        } detail: {
            blockDetail
        }
        .frame(minWidth: 880, minHeight: 560)
        .navigationTitle("clawpypaste")
        .onAppear { browser.refresh() }
        .toolbar { toolbar }
    }

    // MARK: - Sidebar

    private var sessionList: some View {
        VStack(spacing: 0) {
            TextField("Search sessions…", text: $browser.search)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            Divider()

            List(browser.filteredSessions, id: \.url, selection: $browser.selectedSessionURL) { info in
                let meta = browser.meta(for: info)
                SessionRow(
                    info: info,
                    title: browser.displayName(for: info),
                    color: meta.swiftUIColor,
                    cwd: meta.cwd
                )
                .tag(info.url)
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Text("\(browser.filteredSessions.count) of \(browser.sessions.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    browser.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Re-scan sessions")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 300)
    }

    // MARK: - Detail

    private var blockDetail: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            blockFilterBar
            Divider()
            if browser.filteredBlocks.isEmpty {
                emptyDetail
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

    private var detailHeader: some View {
        HStack(spacing: 10) {
            if let url = browser.selectedSessionURL,
               let info = browser.sessions.first(where: { $0.url == url })
            {
                let meta = browser.meta(for: info)
                if let color = meta.swiftUIColor {
                    Circle().fill(color).frame(width: 10, height: 10)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(browser.displayName(for: info))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if let cwd = meta.cwd {
                        Text(cwd.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Text(timeAgo(info.modifiedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Pick a session")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var blockFilterBar: some View {
        HStack(spacing: 8) {
            TextField("Filter blocks", text: $browser.blockSearch)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(nil, label: "All")
                    ForEach(BlockKind.allCases, id: \.self) { k in
                        chip(k, label: k.label)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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

    private var emptyDetail: some View {
        VStack {
            Spacer()
            Text("No blocks")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                browser.resume()
            } label: {
                Label("Resume in iTerm", systemImage: "play.fill")
            }
            .disabled(browser.selectedSessionURL == nil)
            .help("Open a new iTerm tab and run claude --resume")
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60       { return "now" }
        if delta < 3600     { return "\(Int(delta / 60))m ago" }
        if delta < 86400    { return "\(Int(delta / 3600))h ago" }
        if delta < 604800   { return "\(Int(delta / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Sidebar row

private struct SessionRow: View {
    let info: ActiveSession.Info
    let title: String
    let color: Color?
    let cwd: String?

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
