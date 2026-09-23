import AppKit

/// A small regression check for the sidebar, whose rows once selected nothing when clicked.
/// It drives the real sidebar table and exits 0 when everything behaves:
///
///     DUSTPAN_DEMO=1 DUSTPAN_UITEST=1 build/Dustpan.app/Contents/MacOS/Dustpan
@MainActor
enum UITest {
    static func runIfRequested(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["DUSTPAN_UITEST"] != nil else { return }
        while model.phase != .ready { try? await Task.sleep(for: .milliseconds(200)) }
        try? await Task.sleep(for: .milliseconds(500))

        guard let table = NSApp.windows.lazy.compactMap({ $0.contentView.map(tables) }).first?.first else {
            finish(["no sidebar table found"])
        }
        var failures: [String] = []
        // Row 0 is Overview, row 1 the section header, then one row per category.
        func select(_ row: Int) async {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            try? await Task.sleep(for: .milliseconds(400))
        }

        let categories = model.categoriesWithFindings
        for (offset, category) in categories.enumerated() where !model.asksBeforeOpening(category) {
            await select(offset + 2)
            if model.sidebar != .category(category) {
                failures.append("clicking \(category) showed \(String(describing: model.sidebar))")
            }
        }
        await select(0)
        if model.sidebar != .overview { failures.append("clicking Overview showed \(String(describing: model.sidebar))") }

        if let offset = categories.firstIndex(where: model.asksBeforeOpening) {
            let risky = categories[offset]
            await select(offset + 2)
            if model.pendingReveal != .category(risky) { failures.append("\(risky) opened without asking") }
            if model.sidebar != .overview { failures.append("\(risky) changed the page before it was confirmed") }
            if table.selectedRow != 0 { failures.append("the highlight stayed on \(risky) after asking") }
            model.confirmReveal()
            if model.sidebar != .category(risky) { failures.append("confirming \(risky) didn't open it") }
        } else {
            failures.append("no category asks before opening; the demo data should have one")
        }
        finish(failures)
    }

    private static func tables(in view: NSView) -> [NSTableView] {
        ((view as? NSTableView).map { [$0] } ?? []) + view.subviews.flatMap(tables)
    }

    private static func finish(_ failures: [String]) -> Never {
        for failure in failures { fputs("UITEST FAIL: \(failure)\n", stderr) }
        fputs(failures.isEmpty ? "UITEST PASS\n" : "UITEST: \(failures.count) failure(s)\n", stderr)
        exit(failures.isEmpty ? 0 : 1)
    }
}
