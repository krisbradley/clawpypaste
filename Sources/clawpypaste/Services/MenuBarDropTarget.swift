import AppKit

// Transparent NSView that overlays the status item button and turns it into
// a drag-and-drop target. Files (images, text) and selected strings dropped
// here get sent to Claude via the same paste-into-frontmost-terminal flow
// that the screenshot feature uses.
final class MenuBarDropTarget: NSView {
    var onDropImage: ((NSImage) -> Void)?
    var onDropText: ((String) -> Void)?
    var onDropFileURL: ((URL) -> Void)?

    private var isHovered: Bool = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .png,
            .tiff,
            .string,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isHovered = true
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHovered = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            isHovered = false
            needsDisplay = true
        }

        let pb = sender.draggingPasteboard

        // File URLs first — Finder, screenshot, anything draggable from disk.
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let first = urls.first {
            if isImageFile(first), let img = NSImage(contentsOf: first) {
                onDropImage?(img)
                return true
            } else {
                onDropFileURL?(first)
                return true
            }
        }

        // Raw image data (browser drag of a non-saved image).
        if let img = NSImage(pasteboard: pb) {
            onDropImage?(img)
            return true
        }

        // Plain text selection from any app.
        if let text = pb.string(forType: .string), !text.isEmpty {
            onDropText?(text)
            return true
        }

        return false
    }

    // Light visual cue when something is being dragged over the icon.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovered {
            NSColor.systemBlue.withAlphaComponent(0.25).setFill()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            path.fill()
        }
    }

    private func isImageFile(_ url: URL) -> Bool {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "tif", "bmp"]
        return imageExts.contains(url.pathExtension.lowercased())
    }
}
