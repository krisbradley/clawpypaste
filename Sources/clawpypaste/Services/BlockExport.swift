import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Getting a block out of the app by means other than a plain copy:
// drag-and-drop, saving to a file, and rendering to an image.
@MainActor
enum BlockExport {
    // MARK: - File naming

    private static let extensions: [String: String] = [
        "swift": "swift", "python": "py", "py": "py", "javascript": "js", "js": "js",
        "typescript": "ts", "ts": "ts", "tsx": "tsx", "jsx": "jsx", "bash": "sh", "sh": "sh",
        "zsh": "sh", "shell": "sh", "json": "json", "yaml": "yaml", "yml": "yaml",
        "toml": "toml", "html": "html", "css": "css", "sql": "sql", "go": "go",
        "rust": "rs", "rs": "rs", "ruby": "rb", "rb": "rb", "java": "java",
        "kotlin": "kt", "c": "c", "cpp": "cpp", "c++": "cpp", "markdown": "md",
        "md": "md", "xml": "xml", "dockerfile": "Dockerfile", "diff": "diff",
        "patch": "patch", "ini": "ini", "lua": "lua", "php": "php",
    ]

    // A sensible filename: a tool's file_path title wins, else "snippet.<ext>".
    static func suggestedFilename(for block: Block) -> String {
        if let title = block.title, title.contains("/") || title.contains(".") {
            let last = (title as NSString).lastPathComponent
            if last.contains("."), !last.hasPrefix("."), !last.contains(" ") { return last }
        }
        switch block.kind {
        case .table: return "table.tsv"
        case .markdown, .message, .section, .quote: return "note.md"
        default: break
        }
        let lang = block.language?.lowercased() ?? ""
        let ext = extensions[lang] ?? "txt"
        return ext == "Dockerfile" ? "Dockerfile" : "snippet.\(ext)"
    }

    // Tables save as TSV; everything else saves as its raw content.
    static func fileContents(for block: Block) -> String {
        if block.kind == .table, let parsed = TableParser.parse(block.content) {
            return parsed.toTSV()
        }
        return block.content
    }

    static func saveWithPanel(_ block: Block) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename(for: block)
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try fileContents(for: block).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("save failed: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    // MARK: - Drag

    // What a drag carries: HTML + plain text (same as a click), plus a file
    // for code/tables so dropping on Finder or the Desktop creates one.
    static func dragItem(for block: Block) -> BlockDragItem {
        let rich = RichCopy.defaultPayload(for: block)
        let wantsFile = block.isCodeLike || block.kind == .table
        return BlockDragItem(
            html: Clipboard.withCharset(rich?.html ?? "<pre>\(escape(block.content))</pre>"),
            plain: rich?.plain ?? block.content,
            fileName: wantsFile ? suggestedFilename(for: block) : nil,
            fileContents: fileContents(for: block)
        )
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Image

    private static func maxImageWidth(for block: Block) -> CGFloat {
        if block.kind == .table { return 1600 }
        return block.isCodeLike ? 1300 : 1000
    }

    // Renders the block as a styled card image and puts it on the clipboard
    // as PNG + TIFF, for destinations that mangle pasted text.
    static func copyAsImage(_ block: Block) {
        guard let cg = renderImage(block),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        if let tiff = NSImage(cgImage: cg, size: .zero).tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    static func pngData(_ block: Block) -> Data? {
        renderImage(block).flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    private static func renderImage(_ block: Block) -> CGImage? {
        if block.kind == .table, let parsed = TableParser.parse(block.content) {
            return TableImage.render(parsed)
        }
        let renderer = ImageRenderer(content: BlockImageCard(block: block))
        renderer.scale = 2
        // Two passes: measure the unwrapped (ideal) width, then render at
        // min(ideal, cap) so long text wraps AND the height grows to fit.
        // A single unconstrained pass sized height for one line and clipped.
        guard let ideal = renderer.cgImage else { return nil }
        let idealWidth = CGFloat(ideal.width) / renderer.scale
        renderer.proposedSize = ProposedViewSize(width: min(idealWidth, maxImageWidth(for: block)), height: nil)
        return renderer.cgImage
    }
}

// The card drawn by copyAsImage. Always light so it reads on any background.
private struct BlockImageCard: View {
    let block: Block

    var body: some View {
        content
            .padding(24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var content: some View {
        if block.kind == .table, let parsed = TableParser.parse(block.content) {
            tableView(parsed)
        } else if block.isCodeLike {
            Text(SyntaxHighlighter.highlight(block.content, language: block.language, fontSize: 18))
                .font(.system(size: 18, design: .monospaced))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(MarkdownRenderer.render(block.content))
                .font(.system(size: 20))
                .foregroundStyle(.black)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tableView(_ t: ParsedTable) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(t.header.enumerated()), id: \.offset) { _, h in
                    cell(Transformer.stripMarkdown(h), header: true)
                }
            }
            ForEach(Array(t.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(0..<t.header.count, id: \.self) { i in
                        cell(i < row.count ? Transformer.stripMarkdown(row[i]) : "", header: false)
                    }
                }
            }
        }
        .overlay(Rectangle().stroke(Color(white: 0.75), lineWidth: 1))
    }

    // Cells size to their content (up to a readable wrap width) — with an
    // unconstrained ImageRenderer proposal, maxWidth: .infinity collapsed
    // the table to a tiny strip.
    private func cell(_ text: String, header: Bool) -> some View {
        Text(text)
            .font(.system(size: 20, weight: header ? .semibold : .regular))
            .foregroundStyle(.black)
            // Short cells stay on one line; only long ones wrap, at 420pt.
            .modifier(CellWidth(wraps: text.count > 40))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(header ? Color(white: 0.94) : Color.white)
            .border(Color(white: 0.75), width: 0.5)
    }
}

private struct CellWidth: ViewModifier {
    let wraps: Bool
    func body(content: Content) -> some View {
        if wraps {
            content.frame(width: 420, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            content.fixedSize()
                .frame(minWidth: 40, alignment: .leading)
        }
    }
}

// Tables are drawn directly with AppKit at measured column widths. SwiftUI's
// Grid under ImageRenderer mis-sized cells and clipped rows.
enum TableImage {
    private static let font = NSFont.systemFont(ofSize: 20)
    private static let headerFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
    private static let padX: CGFloat = 16, padY: CGFloat = 10, margin: CGFloat = 24
    private static let maxColWidth: CGFloat = 420
    private static let line = NSColor(white: 0.75, alpha: 1)

    static func render(_ t: ParsedTable, scale: CGFloat = 2) -> CGImage? {
        let cols = t.header.count
        guard cols > 0 else { return nil }
        let header = t.header.map { Transformer.stripMarkdown($0) }
        let rows = t.rows.map { r in (0..<cols).map { i in i < r.count ? Transformer.stripMarkdown(r[i]) : "" } }

        func attr(_ s: String, _ isHeader: Bool) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: isHeader ? headerFont : font, .foregroundColor: NSColor.black])
        }
        func size(_ s: String, _ isHeader: Bool, width: CGFloat) -> CGSize {
            attr(s, isHeader).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        }

        // Column width = widest single-line cell, capped (long cells wrap).
        var colW = [CGFloat](repeating: 40, count: cols)
        for i in 0..<cols {
            let cells = [(header[i], true)] + rows.map { ($0[i], false) }
            for (text, isH) in cells {
                colW[i] = max(colW[i], min(ceil(size(text, isH, width: .greatestFiniteMagnitude).width), maxColWidth))
            }
        }
        let allRows = [(header, true)] + rows.map { ($0, false) }
        let rowH: [CGFloat] = allRows.map { (cells, isH) in
            (0..<cols).map { ceil(size(cells[$0], isH, width: colW[$0]).height) }.max()! + padY * 2
        }
        let tableW = colW.reduce(0, +) + padX * 2 * CGFloat(cols)
        let tableH = rowH.reduce(0, +)
        let W = tableW + margin * 2, H = tableH + margin * 2

        let px = (Int(W * scale), Int(H * scale))
        guard let ctx = CGContext(data: nil, width: px.0, height: px.1, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        // Flip so y grows downward.
        ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
        let flipped = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = flipped

        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
        var y = margin
        for (r, (cells, isH)) in allRows.enumerated() {
            var x = margin
            for c in 0..<cols {
                let cellRect = NSRect(x: x, y: y, width: colW[c] + padX * 2, height: rowH[r])
                (isH ? NSColor(white: 0.94, alpha: 1) : NSColor.white).setFill()
                cellRect.fill()
                line.setStroke()
                let border = NSBezierPath(rect: cellRect); border.lineWidth = 1; border.stroke()
                attr(cells[c], isH).draw(with: NSRect(x: x + padX, y: y + padY, width: colW[c], height: rowH[r] - padY * 2),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
                x += colW[c] + padX * 2
            }
            y += rowH[r]
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}

// What a drag carries (consumed by DragHandle's BlockPromiseProvider).
struct BlockDragItem {
    let html: String
    let plain: String
    let fileName: String?
    let fileContents: String
}
