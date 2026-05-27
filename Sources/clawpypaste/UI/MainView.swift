import SwiftUI

// Shared list view used by both the MenuBarExtra popover and the detached window.
struct MainView: View {
    @ObservedObject var store: SessionStore
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider()
            if store.filteredBlocks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.filteredBlocks) { block in
                            BlockRow(
                                block: block,
                                isRecentlyCopied: store.recentlyCopiedId == block.id,
                                isPinned: store.isPinned(block),
                                onCopy: { store.copy(block) },
                                onTogglePin: { store.togglePin(block) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: compact ? 420 : nil, height: compact ? 520 : nil)
        .frame(minWidth: compact ? nil : 520, minHeight: compact ? nil : 600)
    }

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
                store.resumeAuto()
            } label: {
                if store.manuallyPinnedSession == nil {
                    Label("Most recent (auto) ✓", systemImage: "clock")
                } else {
                    Label("Most recent (auto)", systemImage: "clock")
                }
            }
            if !store.recentSessions.isEmpty {
                Divider()
                ForEach(store.recentSessions, id: \.url) { info in
                    Button {
                        store.switchTo(info)
                    } label: {
                        let isCurrent = store.manuallyPinnedSession == info.url
                        // NSMenu doesn't render SwiftUI shapes inside Button
                        // labels, so we encode the color as a leading dot
                        // character tinted by NSAttributedString fallback.
                        Text("\(colorDot(for: store.meta(for: info)))  \(store.displayName(for: info)) — \(timeAgo(info.modifiedAt))\(isCurrent ? "  ✓" : "")")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let color = store.activeMeta?.swiftUIColor {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                }
                Text(store.activeDisplayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // NSMenu items inside a SwiftUI Menu render their label as a plain string,
    // so SwiftUI shapes/colored views don't survive. We fall back to a colored
    // filled-circle emoji glyph as a leading "dot."
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

    private func timeAgo(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60      { return "now" }
        if delta < 3600    { return "\(Int(delta / 60))m ago" }
        if delta < 86400   { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86400))d ago"
    }

    private var filterBar: some View {
        VStack(spacing: 6) {
            TextField("Search blocks", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

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
}
