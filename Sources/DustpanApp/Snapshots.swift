import AppKit
import DustpanCore

/// Renders the app's own windows to PNG files, for the README and for checking the UI without
/// Screen Recording permission. Start the app with `DUSTPAN_SNAPSHOT_DIR=/some/folder`;
/// add `DUSTPAN_SNAPSHOT_APPEARANCE=dark` or `light` to force one, and `DUSTPAN_DEMO=1`
/// to show made-up data instead of your own. The app quits when it's done.
@MainActor
enum Snapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["DUSTPAN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func runIfRequested(_ model: AppModel) async {
        guard let directory else { return }
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

    private static func splitViews(in view: NSView) -> [NSSplitView] {
        ((view as? NSSplitView).map { [$0] } ?? []) + view.subviews.flatMap(splitViews)
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && !$0.isSheet && $0.contentView != nil }
    }

    private static func capture(_ window: NSWindow?, to url: URL) {
        // The frame view includes the title bar and toolbar, not just the content.
        // Always render at 2x, whichever display the window happens to be on.
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ) else { return }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
