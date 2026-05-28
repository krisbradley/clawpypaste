#!/usr/bin/env swift
// Renders the 🦀 emoji to PNGs at all the sizes iconutil needs to build an
// .icns. Designed to be run during build-app.sh.
//
// Usage: swift tools/gen-icon.swift <output-iconset-dir>
//   e.g. swift tools/gen-icon.swift .build/AppIcon.iconset

import AppKit
import Foundation

let sizes: [(name: String, side: Int)] = [
    ("icon_16x16.png",     16),
    ("icon_16x16@2x.png",  32),
    ("icon_32x32.png",     32),
    ("icon_32x32@2x.png",  64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png", 1024),
]

let outDir = CommandLine.arguments.dropFirst().first ?? "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func renderIcon(side: Int) -> NSImage {
    let size = CGFloat(side)
    let canvas = NSSize(width: size, height: size)
    let image = NSImage(size: canvas)
    image.lockFocus()

    // Soft beach-sand background with a squircle-ish rounded rect — gives the
    // crab somewhere to live and makes the icon legible at small sizes against
    // any wallpaper or dock theme.
    let radius = size * 0.225
    let bgRect = NSRect(origin: .zero, size: canvas)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.90, alpha: 1.0).setFill()
    bgPath.fill()

    // Thin inner border so the icon reads on light backgrounds (dock, finder
    // sidebar). Half a point at 16x is invisible; gets crisp at 1024.
    NSColor(white: 0.0, alpha: 0.07).setStroke()
    let border = NSBezierPath(
        roundedRect: bgRect.insetBy(dx: 0.5, dy: 0.5),
        xRadius: radius,
        yRadius: radius
    )
    border.lineWidth = max(0.5, size / 256)
    border.stroke()

    // The crab itself.
    let str = "🦀" as NSString
    let fontSize = size * 0.72
    let font = NSFont.systemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let measured = str.size(withAttributes: attrs)
    let origin = NSPoint(
        x: (size - measured.width) / 2,
        y: (size - measured.height) / 2 - size * 0.02  // nudge down slightly for optical balance
    )
    str.draw(at: origin, withAttributes: attrs)

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String) -> Bool {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { return false }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        return false
    }
}

for entry in sizes {
    let image = renderIcon(side: entry.side)
    let path = "\(outDir)/\(entry.name)"
    if writePNG(image, to: path) {
        FileHandle.standardError.write("  \(entry.name) (\(entry.side)px)\n".data(using: .utf8)!)
    } else {
        FileHandle.standardError.write("  FAILED to write \(entry.name)\n".data(using: .utf8)!)
        exit(1)
    }
}
