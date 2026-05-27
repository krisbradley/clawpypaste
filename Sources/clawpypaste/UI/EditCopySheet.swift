import SwiftUI

// Sheet that lets the user freely edit a block's text before copying it.
// Available on every block via the right-click context menu.
struct EditCopySheet: View {
    let initial: String
    let isCodeLike: Bool
    let onCopy: (String) -> Void

    @State private var draft: String
    @Environment(\.dismiss) private var dismiss

    init(initial: String, isCodeLike: Bool, onCopy: @escaping (String) -> Void) {
        self.initial = initial
        self.isCodeLike = isCodeLike
        self.onCopy = onCopy
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit and copy")
                    .font(.headline)
                Spacer()
                Button("Reset") { draft = initial }
                    .disabled(draft == initial)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            TextEditor(text: $draft)
                .font(.system(size: 12, design: isCodeLike ? .monospaced : .default))
                .frame(minWidth: 520, minHeight: 380)
                .padding(8)

            Divider()

            HStack {
                Text("\(draft.count) chars, \(draft.split(whereSeparator: \.isNewline).count) lines")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Copy") {
                    onCopy(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.isEmpty)
            }
            .padding(12)
        }
    }
}
