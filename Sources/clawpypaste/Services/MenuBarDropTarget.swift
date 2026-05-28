import AppKit

// Transparent NSView that overlays the status item button and turns it into
// a drag-and-drop target. Files (images, text) and selected strings dropped
// here get sent to Claude via the same paste-into-frontmost-terminal flow
// that the screenshot feature uses.
//
// NSStatusBarButton's default event handling can swallow drag events targeted
// at simple `addSubview` children. We sidestep that by:
//   1. Using Auto Layout to fully cover the button at all times
//   2. Marking the view as a drag destination explicitly in init
//   3. Logging at every step so we can see in Console where the chain breaks
final class MenuBarDropTarget: NSView {
    var onDropImage: ((NSImage) -> Void)?
    var onDropText: ((String) -> Void)?
    var onDropFileURL: ((URL) -> Void)?

    private var isHovered: Bool = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .png,
            .tiff,
            .string,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("public.url"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ])
        NSLog("drop: MenuBarDropTarget initialized, types: \(registeredDraggedTypes)")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "<none>"
        NSLog("drop: draggingEntered, available types: \(types)")
        isHovered = true
        needsDisplay = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        NSLog("drop: draggingExited")
        isHovered = false
        needsDisplay = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            isHovered = false
            needsDisplay = true
        }
        let pb = sender.draggingPasteboard
        let types = pb.types?.map(\.rawValue).joined(separator: ", ") ?? "<none>"
        NSLog("drop: performDragOperation, types: \(types)")

        // File URLs first — Finder, screenshot, anything draggable from disk.
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let first = urls.first {
            NSLog("drop: got file URL: \(first.path)")
            if isImageFile(first), let img = NSImage(contentsOf: first) {
                onDropImage?(img)
            } else {
                onDropFileURL?(first)
            }
            return true
        }
        // Raw image data (browser drag of a non-saved image).
        if let img = NSImage(pasteboard: pb) {
            NSLog("drop: got raw image data")
            onDropImage?(img)
            return true
        }
        // Plain text selection from any app.
        if let text = pb.string(forType: .string), !text.isEmpty {
            NSLog("drop: got text string (\(text.count) chars)")
            onDropText?(text)
            return true
        }
        NSLog("drop: nothing recognizable on pasteboard")
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
