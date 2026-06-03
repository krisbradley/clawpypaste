import SwiftUI
import AppKit

struct BlockRow: View {
    let block: Block
    let isRecentlyCopied: Bool
    let isPinned: Bool
    let isSelected: Bool
    let onCopy: () -> Void
    let onCopyAs: (String) -> Void
    let onCopyRich: (String, String) -> Void
    let onTogglePin: () -> Void
    let onInject: () -> Void

    @State private var showingEditSheet = false
    @State private var showingSnippetSheet = false

    private var maxPreviewLines: Int {
        switch block.kind {
        case .code, .toolResult, .toolInput: return 8
        case .table: return 8
        case .markdown, .section, .message: return 5
        case .path, .url: return 1
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(isPinned ? Color.yellow : Color.secondary.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin" : "Pin")

            Button(action: handlePrimaryAction) {
                HStack(alignment: .top, spacing: 10) {
                    kindBadge
                    VStack(alignment: .leading, spacing: 3) {
                        if let title = block.title, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        sourceSessionChip
                        previewBody
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 6) {
                            if let lang = block.language, !lang.isEmpty {
                                Text(lang)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            if block.lineCount > 1 {
                                Text("\(block.lineCount) lines")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            if SnippetEngine.hasPlaceholders(block.content) {
                                Text("• has {{vars}}")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.indigo)
                            }
                            Spacer()
                            if isRecentlyCopied {
                                Text("copied")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 10)
                .padding(.leading, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .draggable(block.content) {
                Text(block.preview)
                    .font(.system(size: 11, design: block.isCodeLike ? .monospaced : .default))
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: 300)
            }
            .contextMenu { contextMenu }
        }
        .padding(.leading, 4)
        .background(rowBackground)
        .sheet(isPresented: $showingEditSheet) {
            EditCopySheet(
                initial: block.content,
                isCodeLike: block.isCodeLike,
                onCopy: { text in onCopyAs(text) }
            )
        }
        .sheet(isPresented: $showingSnippetSheet) {
            SnippetFillSheet(
                template: block.content,
                placeholders: SnippetEngine.placeholders(in: block.content),
                isCodeLike: block.isCodeLike,
                onCopy: { text in onCopyAs(text) }
            )
        }
    }

    // Small "from session …" chip with a colored dot, shown in history
    // mode so the user can tell where each block came from.
    @ViewBuilder
    private var sourceSessionChip: some View {
        if let src = block.sourceSession {
            HStack(spacing: 4) {
                if let color = sessionColor(src.agentColor) {
                    Circle().fill(color).frame(width: 6, height: 6)
                }
                Text(src.title ?? "(untitled session)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func sessionColor(_ raw: String?) -> Color? {
        guard let raw = raw?.lowercased() else { return nil }
        switch raw {
        case "red":           return .red
        case "orange":        return .orange
        case "yellow":        return .yellow
        case "green":         return .green
        case "mint", "teal":  return .mint
        case "cyan":          return .cyan
        case "blue":          return .blue
        case "indigo":        return .indigo
        case "purple":        return .purple
        case "pink":          return .pink
        case "brown":         return .brown
        case "gray", "grey":  return .gray
        default:              return nil
        }
    }

    // MARK: - Smart click on path / URL

    // Default click on a path opens it in Finder; URL opens in the browser.
    // Other kinds copy. Holding ⌘ on path/URL falls back to copy so you can
    // still grab the literal text when you need it.
    private func handlePrimaryAction() {
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        switch block.kind {
        case .path where !cmdHeld:
            openPath(block.content)
        case .url where !cmdHeld:
            openURL(block.content)
        default:
            onCopy()
        }
    }

    private func openPath(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip ":line" or ":line:col" suffixes Claude often appends.
        let cleaned = trimmed.replacingOccurrences(
            of: ":\\d+(:\\d+)?$",
            with: "",
            options: .regularExpression
        )
        let expanded = (cleaned as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expanded)])
        } else {
            onCopy()
        }
    }

    private func openURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { onCopy(); return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Right-click menu

    @ViewBuilder
    private var contextMenu: some View {
        if block.kind == .path {
            Button("Open in Finder") { openPath(block.content) }
            Button("Copy path") { onCopy() }
            Divider()
        } else if block.kind == .url {
            Button("Open in browser") { openURL(block.content) }
            Button("Copy URL") { onCopy() }
            Divider()
        } else {
            Button("Copy") { onCopy() }
        }

        if SnippetEngine.hasPlaceholders(block.content) {
            Button("Fill in values…") { showingSnippetSheet = true }
        }

        Button("Edit and copy…") { showingEditSheet = true }

        Divider()

        if block.kind == .table, let parsed = TableParser.parse(block.content) {
            Button("Copy as Markdown") { onCopyAs(parsed.toMarkdown()) }
            Button("Copy as TSV (Slack)") { onCopyAs(parsed.toTSV()) }
            Button("Copy as CSV") { onCopyAs(parsed.toCSV()) }
            Button("Copy as rich text (Docs, Word)") {
                onCopyRich(parsed.toHTML(), parsed.toTSV())
            }
            Divider()
        }

        if mayBenefitFromRichCopy {
            Button("Copy as rich text (Docs, Word)") {
                onCopyRich(
                    Transformer.markdownToHTML(block.content),
                    Transformer.stripMarkdown(block.content)
                )
            }
        }

        if block.isProseLike, Humanizer.looksAIGenerated(block.content) {
            Button("Copy humanized") { onCopyAs(Humanizer.humanize(block.content)) }
        }

        // Generic transforms — gated by applicability.
        if mayBenefitFromStripMarkdown {
            Button("Copy without markdown") { onCopyAs(Transformer.stripMarkdown(block.content)) }
        }
        if Transformer.looksLikeJSON(block.content) {
            Button("Copy as pretty JSON") { onCopyAs(Transformer.prettyJSON(block.content)) }
        }
        if block.kind != .code && block.kind != .markdown {
            Button("Wrap as code fence") {
                onCopyAs(Transformer.wrapInFence(block.content, language: block.language))
            }
        }

        Divider()

        Button("Inject into Claude prompt") { onInject() }
        Button(isPinned ? "Unpin" : "Pin") { onTogglePin() }
    }

    private var mayBenefitFromStripMarkdown: Bool {
        guard block.isProseLike else { return false }
        let c = block.content
        return c.contains("**") || c.contains("__") || c.contains("`") || c.contains("[")
            || c.range(of: "^#{1,6} ", options: [.regularExpression, .anchored]) != nil
    }

    // Same gate as strip-markdown: only show "Copy as rich text" when the
    // source actually contains markdown markers that would translate to
    // styling. Plain prose with no markup has nothing to render and would
    // just confuse the menu.
    private var mayBenefitFromRichCopy: Bool {
        mayBenefitFromStripMarkdown
    }

    // MARK: - Preview body

    @ViewBuilder
    private var previewBody: some View {
        if block.kind == .code {
            Text(SyntaxHighlighter.highlight(
                block.previewLines(maxPreviewLines),
                language: block.language
            ))
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(maxPreviewLines)
            .multilineTextAlignment(.leading)
        } else if block.isCodeLike {
            Text(block.previewLines(maxPreviewLines))
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(maxPreviewLines)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
        } else if block.isProseLike {
            Text(markdownPreview)
                .font(.system(size: 12))
                .lineLimit(maxPreviewLines)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
        } else {
            Text(block.previewLines(maxPreviewLines))
                .font(.system(size: 12))
                .lineLimit(maxPreviewLines)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
        }
    }

    private var markdownPreview: AttributedString {
        MarkdownRenderer.render(block.previewLines(maxPreviewLines))
    }

    // MARK: - Visual

    private var rowBackground: Color {
        if isSelected      { return Color.accentColor.opacity(0.18) }
        if isRecentlyCopied { return Color.green.opacity(0.12) }
        if isPinned        { return Color.yellow.opacity(0.06) }
        return Color.clear
    }

    private var kindBadge: some View {
        Text(block.kind.label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor)
            .clipShape(Capsule())
            .frame(minWidth: 60)
    }

    private var badgeColor: Color {
        switch block.kind {
        case .code:       return .blue
        case .markdown:   return .brown
        case .table:      return .mint
        case .toolResult: return .purple
        case .toolInput:  return .indigo
        case .path:       return .orange
        case .url:        return .teal
        case .message:    return .gray
        case .section:    return .pink
        }
    }
}
