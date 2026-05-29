import AppKit

// Crab menu bar icon. Renders the 🦀 emoji to a high-res bitmap, then
// thresholds every non-transparent pixel to pure black so the result is a
// monochrome silhouette. Marked as template so macOS tints it to match the
// menu bar appearance (white in dark mode, black in light mode).
//
// The dock icon stays full-color since dock icons aren't templated.
enum CrabIcon {
    static func menuBarImage(style: Preferences.IconStyle = .silhouette) -> NSImage {
        switch style {
        case .silhouette:
            let color = renderEmoji("🦀", canvas: NSSize(width: 22, height: 22), fontSize: 18)
            return monochromeSilhouette(from: color, logicalSize: NSSize(width: 22, height: 22))
        case .color:
            return renderEmoji("🦀", canvas: NSSize(width: 22, height: 22), fontSize: 17)
        case .clipboard:
            let img = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "clawpypaste")
                ?? NSImage()
            img.isTemplate = true
            return img
        }
    }

    static func dockImage() -> NSImage {
        renderEmoji("🦀", canvas: NSSize(width: 512, height: 512), fontSize: 420)
    }

    // MARK: - Emoji rendering

    private static func renderEmoji(_ emoji: String, canvas: NSSize, fontSize: CGFloat) -> NSImage {
        let image = NSImage(size: canvas)
        image.lockFocus()
        let str = emoji as NSString
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let measured = str.size(withAttributes: attrs)
        let origin = NSPoint(
            x: (canvas.width - measured.width) / 2,
            y: (canvas.height - measured.height) / 2
        )
        str.draw(at: origin, withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    // MARK: - Color → black silhouette template

    private static func monochromeSilhouette(from source: NSImage, logicalSize: NSSize) -> NSImage {
        // Render at 2x for retina sharpness, then publish at the logical size
        // so the menu bar uses the high-res rep.
        let scale: CGFloat = 2
        let width = Int(logicalSize.width * scale)
        let height = Int(logicalSize.height * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else {
            source.isTemplate = true
            return source
        }
        rep.size = logicalSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(
            in: NSRect(origin: .zero, size: logicalSize),
            from: NSRect(origin: .zero, size: source.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        // Threshold: any non-transparent pixel becomes pure black at full
        // opacity; transparent pixels stay transparent. The result is a
        // crisp silhouette that template tinting can recolor cleanly.
        guard let data = rep.bitmapData else {
            source.isTemplate = true
            return source
        }
        let bytesPerRow = rep.bytesPerRow
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let alpha = data[offset + 3]
                if alpha > 24 {
                    data[offset]     = 0
                    data[offset + 1] = 0
                    data[offset + 2] = 0
                    data[offset + 3] = 255
                } else {
                    data[offset + 3] = 0
                }
            }
        }

        let result = NSImage(size: logicalSize)
        result.addRepresentation(rep)
        result.isTemplate = true
        return result
    }
}
