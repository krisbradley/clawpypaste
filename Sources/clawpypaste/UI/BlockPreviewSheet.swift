import SwiftUI

// Full-content view of a block (the list truncates to 5–8 lines).
// Space or Esc closes; Return copies.
struct BlockPreviewSheet: View {
    let block: Block
    let onCopy: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(block.title ?? block.kind.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(block.lineCount) lines")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                content
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("") { dismiss() }
                    .keyboardShortcut(.space, modifiers: [])
                    .opacity(0).frame(width: 0)
                Spacer()
                Button("Copy") { onCopy(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 560, height: 460)
    }

    @ViewBuilder
    private var content: some View {
        if block.kind == .code {
            Text(SyntaxHighlighter.highlight(block.content, language: block.language, fontSize: 12))
                .font(.system(size: 12, design: .monospaced))
                .fixedSize(horizontal: true, vertical: true)
        } else if block.isCodeLike || block.kind == .table {
            Text(block.content)
                .font(.system(size: 12, design: .monospaced))
                .fixedSize(horizontal: true, vertical: true)
        } else {
            Text(MarkdownRenderer.render(block.content))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
