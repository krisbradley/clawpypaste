import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Native drag source. SwiftUI's .draggable / .onDrag on a Button row never
// started a drag on current macOS, so each row gets a small grip that runs
// an AppKit dragging session directly.
//
// A plain drag carries HTML + plain text (Slack, Docs, Mail, Terminal).
// Option-drag carries a file promise instead, for Finder and the Desktop.
struct DragHandle: NSViewRepresentable {
    let block: Block

    func makeNSView(context: Context) -> DragHandleView {
        let v = DragHandleView()
        v.block = block
        return v
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {
        nsView.block = block
    }
}

final class DragHandleView: NSView, NSDraggingSource {
    var block: Block?
    private var mouseDownEvent: NSEvent?

    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        guard let img = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag")?
            .withSymbolConfiguration(config) else { return }
        let tinted = img.copy() as! NSImage
        tinted.lockFocus()
        NSColor.tertiaryLabelColor.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let r = NSRect(x: (bounds.width - tinted.size.width) / 2,
                       y: (bounds.height - tinted.size.height) / 2,
                       width: tinted.size.width, height: tinted.size.height)
        tinted.draw(in: r)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let block, let start = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x
        let dy = event.locationInWindow.y - start.locationInWindow.y
        guard dx * dx + dy * dy > 9 else { return }   // 3pt threshold
        mouseDownEvent = nil

        // Slack (Electron/Chromium) rejects drags that carry a file promise,
        // so a normal drag is text-only (HTML + plain). Option-drag makes a file.
        let writer: NSPasteboardWriting = event.modifierFlags.contains(.option)
            ? BlockPromiseProvider(block: block)
            : textItem(for: block)
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: dragImage(for: block))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func textItem(for block: Block) -> NSPasteboardItem {
        let drag = MainActor.assumeIsolated { BlockExport.dragItem(for: block) }
        let item = NSPasteboardItem()
        item.setString(drag.html, forType: .html)
        item.setString(drag.plain, forType: .string)
        return item
    }

    private func dragImage(for block: Block) -> NSImage {
        let text = String(block.preview.prefix(60)) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attrs)
        let img = NSImage(size: NSSize(width: min(size.width, 300) + 16, height: size.height + 10))
        img.lockFocus()
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: img.size), xRadius: 6, yRadius: 6).fill()
        text.draw(in: NSRect(x: 8, y: 5, width: min(size.width, 300), height: size.height), withAttributes: attrs)
        img.unlockFocus()
        return img
    }
}

// A file promise (plus the file's text, for apps that don't take files).
final class BlockPromiseProvider: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    let block: Block
    private let fileName: String
    private let fileContents: String

    // Built on the main thread (from mouseDragged); the delegate callbacks
    // below may run elsewhere, so they only read these stored values.
    init(block: Block) {
        self.block = block
        let (item, name) = MainActor.assumeIsolated {
            (BlockExport.dragItem(for: block), BlockExport.suggestedFilename(for: block))
        }
        self.fileName = name
        self.fileContents = item.fileContents
        super.init()
        let ext = (name as NSString).pathExtension
        self.fileType = (UTType(filenameExtension: ext) ?? .plainText).identifier
        self.delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.string]
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .string: return fileContents
        default: return super.pasteboardPropertyList(forType: type)
        }
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        fileName
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        do {
            try fileContents.write(to: url, atomically: true, encoding: .utf8)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
