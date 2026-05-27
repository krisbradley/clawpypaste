import SwiftUI

// Shared list view used by both the MenuBarExtra popover and the detached window.
struct MainView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject private var history = HistoryStore.shared
    let compact: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider()
            content
        }
        .frame(width: compact ? 420 : nil, height: compact ? 520 : nil)
        .frame(minWidth: compact ? nil : 520, minHeight: compact ? nil : 600)
        .background(keyboardShortcuts)
        .onAppear { store.selectFirstIfNeeded() }
        .onChange(of: store.filteredBlocks.map(\.id)) { _ in
            // If filter/search changed and current selection is gone, pick first.
            if let id = store.selectedBlockId,
               !store.filteredBlocks.contains(where: { $0.id == id })
            {
                store.selectedBlockId = store.filteredBlocks.first?.id
            } else {
                store.selectFirstIfNeeded()
            }
        }
    }

    // MARK: - Content list

    @ViewBuilder
    private var content: some View {
        if store.filteredBlocks.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.filteredBlocks) { block in
                            BlockRow(
                                block: block,
                                isRecentlyCopied: store.recentlyCopiedId == block.id,
                                isPinned: store.isPinned(block),
                                isSelected: store.selectedBlockId == block.id,
                                onCopy: { store.copy(block) },
                                onCopyAs: { text in store.copy(block, asText: text) },
                                onTogglePin: { store.togglePin(block) },
                                onInject: { store.inject(block) }
                            )
                            .id(block.id)
                            Divider()
                        }
                    }
                }
                .onChange(of: store.selectedBlockId) { newId in
                    guard let id = newId else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Keyboard shortcuts

    // Hidden buttons attached via .background so they catch keys when the
    // popover has focus. Suppressed while the search field has focus so
    // arrow keys move the text cursor instead of the selection.
    private var keyboardShortcuts: some View {
        Group {
            if !searchFocused {
                Button("") { store.moveSelection(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button("") { store.moveSelection(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("") { store.moveSelection(by: 10) }
                    .keyboardShortcut(.downArrow, modifiers: [.shift])
                Button("") { store.moveSelection(by: -10) }
                    .keyboardShortcut(.upArrow, modifiers: [.shift])
                Button("") { store.copySelected() }
                    .keyboardShortcut(.return, modifiers: [])
            }
            Button("") { searchFocused = true }
                .keyboardShortcut("/", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("clawpypaste")
                    .font(.system(size: 13, weight: .semibold))
                sessionMenu
            }
            Spacer()
            Button(action: { store.rescan() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rescan active session")

            if !compact {
                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quit clawpypaste")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sessionMenu: some View {
        Menu {
            Button {
                store.exitHistoryScope()
                store.resumeAuto()
            } label: {
                let isActive = store.scope == .active && store.manuallyPinnedSession == nil
                Label("Most recent (auto)\(isActive ? " ✓" : "")", systemImage: "clock")
            }
            if !store.recentSessions.isEmpty {
                Divider()
                ForEach(store.recentSessions, id: \.url) { info in
                    Button {
                        store.exitHistoryScope()
                        store.switchTo(info)
                    } label: {
                        let isCurrent = store.scope == .active && store.manuallyPinnedSession == info.url
                        Text("\(colorDot(for: store.meta(for: info)))  \(store.displayName(for: info)) — \(timeAgo(info.modifiedAt))\(isCurrent ? "  ✓" : "")")
                    }
                }
            }
            Divider()
            Button {
                store.enterHistoryScope()
            } label: {
                Label("All sessions (history)\(store.scope == .history ? " ✓" : "")", systemImage: "books.vertical")
            }
            if store.scope == .history {
                Button {
                    history.rebuild()
                } label: {
                    Label("Rebuild history index", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let color = store.activeMeta?.swiftUIColor {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                }
                Text(store.scope == .history ? "All sessions" : store.activeDisplayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if store.scope == .history && history.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 2)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func colorDot(for meta: SessionMeta) -> String {
        guard let color = meta.agentColor?.lowercased() else { return "○" }
        switch color {
        case "red":           return "🔴"
        case "orange":        return "🟠"
        case "yellow":        return "🟡"
        case "green":         return "🟢"
        case "mint", "teal":  return "🟢"
        case "cyan", "blue":  return "🔵"
        case "indigo":        return "🔵"
        case "purple", "pink":return "🟣"
        case "brown":         return "🟤"
        case "gray", "grey":  return "⚫"
        default:              return "○"
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 6) {
            TextField("Search blocks  (press / to focus)", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onSubmit { searchFocused = false }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    kindChip(nil, label: "All")
                    ForEach(BlockKind.allCases, id: \.self) { k in
                        kindChip(k, label: k.label)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func kindChip(_ kind: BlockKind?, label: String) -> some View {
        let isActive = store.kindFilter == kind
        return Button(action: { store.kindFilter = kind }) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(store.blocks.isEmpty ? "No blocks yet" : "No matches")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            if !store.blocks.isEmpty {
                Text("Adjust filters or search")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timeAgo(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60      { return "now" }
        if delta < 3600    { return "\(Int(delta / 60))m ago" }
        if delta < 86400   { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86400))d ago"
    }
}
