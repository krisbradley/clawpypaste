import SwiftUI

struct BlockRow: View {
    let block: Block
    let isRecentlyCopied: Bool
    let isPinned: Bool
    let onCopy: () -> Void
    let onTogglePin: () -> Void

    private var maxPreviewLines: Int {
        switch block.kind {
        case .code, .toolResult, .toolInput: return 8
        case .markdown, .section, .message: return 5
        case .path, .url: return 1
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Star toggles pin without triggering the row's copy action.
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(isPinned ? Color.yellow : Color.secondary.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin" : "Pin")

            Button(action: onCopy) {
                HStack(alignment: .top, spacing: 10) {
                    kindBadge
                    VStack(alignment: .leading, spacing: 3) {
                        if let title = block.title, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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
            // Drag the content out to other apps (editor, Slack, etc).
            // SwiftUI handles tap-vs-drag disambiguation automatically.
            .draggable(block.content) {
                Text(block.preview)
                    .font(.system(size: 11, design: block.isCodeLike ? .monospaced : .default))
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: 300)
            }
        }
        .padding(.leading, 4)
        .background(rowBackground)
    }

    private var rowBackground: Color {
        if isRecentlyCopied { return Color.green.opacity(0.12) }
        if isPinned        { return Color.yellow.opacity(0.06) }
        return Color.clear
    }

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
            // path, url: plain to avoid markdown parser eating underscores etc.
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
        case .toolResult: return .purple
        case .toolInput:  return .indigo
        case .path:       return .orange
        case .url:        return .teal
        case .message:    return .gray
        case .section:    return .pink
        }
    }
}
