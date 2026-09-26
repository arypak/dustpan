import AppKit
import DustpanCore

/// Renders the app's own windows to PNG files, for the README and for checking the UI without
/// Screen Recording permission. Start the app with `DUSTPAN_SNAPSHOT_DIR=/some/folder`;
/// add `DUSTPAN_SNAPSHOT_APPEARANCE=dark` or `light` to force one, and `DUSTPAN_DEMO=1`
/// to show made-up data instead of your own. With `DUSTPAN_SNAPSHOT_TOUR=1` it instead walks
/// through a sweep and saves numbered frames for the README animation; the tour only runs with
/// `DUSTPAN_DEMO=1`. The app quits when it's done.
@MainActor
enum Snapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["DUSTPAN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func runIfRequested(_ model: AppModel) async {
        guard let directory else { return }
        let touring = ProcessInfo.processInfo.environment["DUSTPAN_SNAPSHOT_TOUR"] != nil
        // The animation is published, and it walks through a sweep: never on this Mac's own files.
        if touring && !DemoData.isEnabled {
            fputs("The snapshot tour only runs with DUSTPAN_DEMO=1, on made-up data.\n", stderr)
            NSApp.terminate(nil)
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let appearance = ProcessInfo.processInfo.environment["DUSTPAN_SNAPSHOT_APPEARANCE"]
        let suffix = appearance.map { "-" + $0 } ?? ""
        switch appearance {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }

        mainWindow?.setContentSize(NSSize(width: 1100, height: 720))
        while model.phase != .ready { try? await Task.sleep(for: .milliseconds(200)) }
        try? await Task.sleep(for: .seconds(1))
        // The sidebar remembers the width it was last dragged to; use the default one.
        if let content = mainWindow?.contentView, let split = splitViews(in: content).first {
            split.setPosition(300, ofDividerAt: 0)
            try? await Task.sleep(for: .milliseconds(300))
        }

        if touring {
            await tour(model, into: directory)
            NSApp.terminate(nil)
            return
        }

        let pages = [("overview", SidebarItem.overview)] + model.categoriesWithFindings.map { ($0.rawValue, SidebarItem.category($0)) }
        for (name, page) in pages {
            model.showForSnapshot(page)
            try? await Task.sleep(for: .milliseconds(700))
            capture(mainWindow, to: directory.appendingPathComponent("\(name)\(suffix).png"))
        }

        model.showForSnapshot(.overview)
        model.select(.safe)
        try? await Task.sleep(for: .milliseconds(500))
        capture(mainWindow, to: directory.appendingPathComponent("selected\(suffix).png"))
        model.sheet = .confirm
        try? await Task.sleep(for: .seconds(1))
        capture(NSApp.windows.first { $0.isSheet }, to: directory.appendingPathComponent("confirm\(suffix).png"))
        model.sheet = nil
        model.selection.removeAll()
        NSApp.terminate(nil)
    }

    /// A sweep from start to finish: look around, read an explanation, select, confirm, done.
    /// The sweep itself is pretended, so the tour can't move anything even if run by mistake.
    private static func tour(_ model: AppModel, into directory: URL) async {
        func frame(_ name: String) {
            capture(mainWindow, sheet: NSApp.windows.first { $0.isSheet && $0.isVisible }, to: directory.appendingPathComponent(name + ".png"))
        }
        func pause(_ seconds: Double) async { try? await Task.sleep(for: .milliseconds(Int(seconds * 1000))) }

        // Default buttons only turn blue in the active window.
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
        model.showForSnapshot(.overview)
        await pause(0.7)
        frame("1-overview")
        model.showForSnapshot(.category(.xcode))
        await pause(0.7)
        frame("2-explained")
        model.showForSnapshot(.overview)
        model.select(.safe)
        await pause(0.7)
        frame("3-selected")
        model.sheet = .confirm
        await pause(1.0)
        frame("4-confirm")
        model.pretendSweep()
        await pause(1.0)
        frame("5-result")
        model.finishSweep()
        await pause(1.0)
        frame("6-after")
    }

    private static func splitViews(in view: NSView) -> [NSSplitView] {
        ((view as? NSSplitView).map { [$0] } ?? []) + view.subviews.flatMap(splitViews)
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && !$0.isSheet && $0.contentView != nil }
    }

    private static func capture(_ window: NSWindow?, to url: URL) {
        guard let rep = render(window) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The window with its sheet drawn on top where macOS shows it, the way a screenshot would.
    private static func capture(_ window: NSWindow?, sheet: NSWindow?, to url: URL) {
        guard let window, let base = render(window) else { return }
        guard let sheet, let top = render(sheet) else {
            try? base.representation(using: .png, properties: [:])?.write(to: url)
            return
        }
        let size = base.size
        let image = NSImage(size: size, flipped: false) { _ in
            base.draw(in: NSRect(origin: .zero, size: size))
            let origin = NSPoint(x: sheet.frame.minX - window.frame.minX, y: sheet.frame.minY - window.frame.minY)
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 24
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.set()
            NSBezierPath(roundedRect: NSRect(origin: origin, size: top.size), xRadius: 12, yRadius: 12).addClip()
            top.draw(in: NSRect(origin: origin, size: top.size))
            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: base.pixelsWide, pixelsHigh: base.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The whole window, title bar and toolbar included, always at 2x whichever display it's on.
    private static func render(_ window: NSWindow?) -> NSBitmapImageRep? {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ) else { return nil }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
}
