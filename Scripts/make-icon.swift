#!/usr/bin/env swift
// Draws Dustpan's app icon and writes Resources/AppIcon.icns and Resources/AppIcon.png.
// Usage: swift Scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// A four-pointed sparkle centred on `center`.
func sparkle(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let waist = radius * 0.28
    path.move(to: CGPoint(x: center.x, y: center.y - radius))
    path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + waist, y: center.y - waist))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + waist, y: center.y + waist))
    path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - waist, y: center.y + waist))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - waist, y: center.y - waist))
    path.closeSubpath()
    return path
}

/// A trapezoid with rounded corners: `top` edge narrower than `bottom` edge (y grows downwards).
func tray(topY: CGFloat, topHalf: CGFloat, bottomY: CGFloat, bottomHalf: CGFloat, radius: CGFloat) -> CGPath {
    let cx = canvas / 2
    let points = [
        CGPoint(x: cx - topHalf, y: topY), CGPoint(x: cx + topHalf, y: topY),
        CGPoint(x: cx + bottomHalf, y: bottomY), CGPoint(x: cx - bottomHalf, y: bottomY),
    ]
    let path = CGMutablePath()
    path.move(to: CGPoint(x: (points[3].x + points[0].x) / 2, y: (points[3].y + points[0].y) / 2))
    for index in 0..<4 {
        let corner = points[index]
        let next = points[(index + 1) % 4]
        path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
    }
    path.closeSubpath()
    return path
}

func draw(_ context: CGContext) {
    // y grows downwards from here on, like the numbers in a design tool.
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)

    // Rounded-square base with a soft drop shadow, on Apple's 824 pt icon grid.
    let base = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: base, cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.28))
    context.addPath(squircle)
    context.setFillColor(color(0x0E8F80))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x46E0B8), color(0x0B8577)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // A gentle highlight across the top.
    let shine = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(shine, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 480), options: [])
    context.restoreGState()

    // Handle, leaning back, rising from behind the pan.
    context.saveGState()
    context.translateBy(x: 548, y: 540)
    context.rotate(by: 0.36)
    let handle = CGPath(roundedRect: CGRect(x: -38, y: -330, width: 76, height: 350), cornerWidth: 38, cornerHeight: 38, transform: nil)
    context.setShadow(offset: CGSize(width: 0, height: 8), blur: 18, color: color(0x04443D, 0.35))
    context.addPath(handle)
    context.setFillColor(color(0xF4FFFB))
    context.fillPath()
    context.restoreGState()

    // The pan: wide and low, like one sitting on the floor, with a mint floor you sweep into.
    let pan = tray(topY: 500, topHalf: 232, bottomY: 772, bottomHalf: 318, radius: 52)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 14), blur: 26, color: color(0x04443D, 0.38))
    context.addPath(pan)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    let floor = tray(topY: 536, topHalf: 200, bottomY: 700, bottomHalf: 256, radius: 30)
    context.saveGState()
    context.addPath(floor)
    context.clip()
    let floorGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x9FE7D4), color(0xDDF8F0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(floorGradient, start: CGPoint(x: 512, y: 536), end: CGPoint(x: 512, y: 700), options: [])
    context.restoreGState()

    // Dust on its way in, and a sparkle for the clean that's left behind.
    context.setFillColor(color(0x0B8577, 0.6))
    for (x, y, r) in [(430.0, 662.0, 16.0), (500.0, 676.0, 12.0), (574.0, 656.0, 14.0), (628.0, 674.0, 9.0), (470.0, 632.0, 8.0)] {
        context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
    context.setFillColor(color(0xFFF7CF))
    context.addPath(sparkle(CGPoint(x: 316, y: 330), 78))
    context.addPath(sparkle(CGPoint(x: 410, y: 222), 38))
    context.fillPath()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    draw(context)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try! png(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try! png(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try! png(pixels: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and Resources/AppIcon.png" : "iconutil failed")
