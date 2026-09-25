#!/usr/bin/env swift
// Draws docs/social-preview.png, the 1280×640 card shown when the repo link is shared.
// Upload it in the repo's Settings → General → Social preview.
//
//   swift Scripts/make-social-preview.swift
import AppKit

let size = NSSize(width: 1280, height: 640)
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

guard let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.png")),
      let screenshot = NSImage(contentsOf: root.appendingPathComponent("docs/screenshots/overview-light.png")) else {
    fatalError("run from the repository root, after the screenshots exist")
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// Brand gradient, the same greens as the icon.
NSGradient(starting: color(0x3FD6B0), ending: color(0x0A7468))!.draw(in: NSRect(origin: .zero, size: size), angle: -35)

// The app, bleeding off the right edge.
let shotWidth: CGFloat = 780
let shotHeight = shotWidth * screenshot.size.height / screenshot.size.width
let shot = NSRect(x: 590, y: 64, width: shotWidth, height: shotHeight)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.shadowColor = color(0x042F2A, 0.45)
shadow.set()
color(0xFFFFFF).setFill()
NSBezierPath(roundedRect: shot, xRadius: 16, yRadius: 16).fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: shot, xRadius: 16, yRadius: 16).addClip()
screenshot.draw(in: shot)
NSGraphicsContext.restoreGraphicsState()

// Icon, name, promise.
icon.draw(in: NSRect(x: 52, y: 404, width: 176, height: 176))
let title = NSAttributedString(string: "Dustpan", attributes: [.font: rounded(92, .bold), .foregroundColor: NSColor.white])
title.draw(at: NSPoint(x: 72, y: 282))

let paragraph = NSMutableParagraphStyle()
paragraph.lineSpacing = 4
let tagline = NSAttributedString(string: "See what's filling your Mac,\nthen sweep it into the Trash.", attributes: [
    .font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: color(0xFFFFFF, 0.95),
    .paragraphStyle: paragraph,
])
tagline.draw(in: NSRect(x: 76, y: 168, width: 500, height: 100))

let footer = NSAttributedString(string: "Free & open source · Mac app + CLI · English & Türkçe", attributes: [
    .font: NSFont.systemFont(ofSize: 21, weight: .medium), .foregroundColor: color(0xFFFFFF, 0.82),
])
footer.draw(at: NSPoint(x: 76, y: 92))

NSGraphicsContext.restoreGraphicsState()
let output = root.appendingPathComponent("docs/social-preview.png")
try! rep.representation(using: .png, properties: [:])!.write(to: output)
print("Wrote docs/social-preview.png")
