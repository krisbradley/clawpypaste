import SwiftUI

// When a block contains {{placeholder}} tokens, this sheet collects values
// for each placeholder, substitutes them, and hands the result to onCopy.
struct SnippetFillSheet: View {
    let template: String
    let placeholders: [String]
    let isCodeLike: Bool
    let onCopy: (String) -> Void

    @State private var values: [String: String]
    @Environment(\.dismiss) private var dismiss

    init(template: String, placeholders: [String], isCodeLike: Bool, onCopy: @escaping (String) -> Void) {
        self.template = template
        self.placeholders = placeholders
        self.isCodeLike = isCodeLike
        self.onCopy = onCopy
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: placeholders.map { ($0, "") }))
    }

    private var rendered: String {
        SnippetEngine.fill(template: template, values: values)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Fill in values")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(placeholders, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField(name, text: Binding(
                                get: { values[name] ?? "" },
                                set: { values[name] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: isCodeLike ? .monospaced : .default))
                        }
                    }
                }
                .padding(12)
            }
            .frame(minWidth: 460, minHeight: 160)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(rendered)
                        .font(.system(size: 11, design: isCodeLike ? .monospaced : .default))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(4)
                }
                .frame(maxHeight: 140)
            }
            .padding(12)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Copy") {
                    onCopy(rendered)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }
}
