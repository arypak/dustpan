#!/usr/bin/env swift
// Turns the snapshot tour into docs/demo.gif, with a caption under each frame.
//
//   DUSTPAN_DEMO=1 DUSTPAN_LANG=en DUSTPAN_SNAPSHOT_APPEARANCE=light DUSTPAN_SNAPSHOT_TOUR=1 \
//     DUSTPAN_SNAPSHOT_DIR=/tmp/dustpan-tour build/Dustpan.app/Contents/MacOS/Dustpan
//   swift Scripts/make-demo-gif.swift /tmp/dustpan-tour
import AppKit
import ImageIO
import UniformTypeIdentifiers

let steps: [(frame: String, caption: String, seconds: Double)] = [
    ("1-overview", "See what's filling your Mac, sorted by how safe it is to remove", 2.8),
    ("2-explained", "Every item says what it is and what happens once it's gone", 3.0),
    ("3-selected", "Select everything that grows back on its own in one click", 2.4),
    ("4-confirm", "Confirm. Nothing is deleted: it all goes to the Trash", 2.8),
    ("5-result", "Put anything back from the Trash until you empty it", 2.8),
]

let width: CGFloat = 960
let band: CGFloat = 60

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func frame(_ screenshot: NSImage, number: Int, caption: String) -> CGImage {
    let shotHeight = (width * screenshot.size.height / screenshot.size.width).rounded()
    let size = NSSize(width: width, height: shotHeight + band)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    color(0x0E2F2B).setFill()
    NSRect(origin: .zero, size: size).fill()
    screenshot.draw(in: NSRect(x: 0, y: band, width: width, height: shotHeight))

    // Step number in a mint circle, then the caption.
    let circle = NSRect(x: 22, y: (band - 28) / 2, width: 28, height: 28)
    color(0x46E0B8).setFill()
    NSBezierPath(ovalIn: circle).fill()
    let numberStyle: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: color(0x0B3D36),
    ]
    let number = NSAttributedString(string: "\(number)", attributes: numberStyle)
    number.draw(at: NSPoint(x: circle.midX - number.size().width / 2, y: circle.midY - number.size().height / 2))
    let text = NSAttributedString(string: caption, attributes: [
        .font: NSFont.systemFont(ofSize: 19, weight: .semibold), .foregroundColor: NSColor.white,
    ])
    text.draw(at: NSPoint(x: circle.maxX + 14, y: (band - text.size().height) / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

guard CommandLine.arguments.count > 1 else {
    print("usage: swift Scripts/make-demo-gif.swift <tour folder>")
    exit(64)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/demo.gif")

guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, steps.count, nil) else {
    fatalError("can't write \(output.path)")
}
CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
] as CFDictionary)
for (index, step) in steps.enumerated() {
    guard let screenshot = NSImage(contentsOf: folder.appendingPathComponent(step.frame + ".png")) else {
        fatalError("missing \(step.frame).png in \(folder.path)")
    }
    CGImageDestinationAddImage(destination, frame(screenshot, number: index + 1, caption: step.caption), [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: step.seconds, kCGImagePropertyGIFUnclampedDelayTime: step.seconds,
        ],
    ] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("couldn't finish the GIF") }
print("Wrote docs/demo.gif")
