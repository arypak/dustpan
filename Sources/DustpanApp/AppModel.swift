import AppKit
import DustpanCore
import Observation

typealias RuleCategory = DustpanCore.Category

enum SidebarItem: Hashable {
    case overview
    case category(RuleCategory)
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle, scanning, ready, cleaning
    }

    /// The sweep sheet: first it asks, then it reports. One sheet, so the two never race.
    enum Sheet: Equatable {
        case confirm, result
    }

    var phase: Phase = .idle
    var progress: ScanProgress?
    private(set) var report: ScanReport?
    /// Selected target ids (their paths).
    var selection: Set<String> = []
    /// Findings the user opened or closed. Review findings start open, the rest closed.
    var toggledOpen: Set<String> = []
    var sidebar: SidebarItem? = .overview
    var sheet: Sheet?
    var result: CleanResult?
    /// Bytes this session has moved to the Trash.
    private(set) var sweptBytes: Int64 = 0

    var projectRoots: [URL] {
        didSet { UserDefaults.standard.set(projectRoots.map(\.path), forKey: "projectRoots") }
    }

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "projectRoots")
        projectRoots = saved?.map { URL(fileURLWithPath: $0) }
            ?? ProjectScanner.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    // MARK: Scanning

    func scan() {
        scanTask?.cancel()
        phase = .scanning
        progress = nil
        if DemoData.isEnabled {
            report = DemoData.report()
            phase = .ready
            return
        }
        let options = ScanOptions(projectRoots: projectRoots)
        scanTask = Task { [weak self] in
            let report = await Scanner(options: options).scan { progress in
                Task { @MainActor in
                    guard let self, self.phase == .scanning else { return }
                    self.progress = progress
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.report = report
            let ids = Set(report.findings.flatMap(\.targets).map(\.id))
            self.selection.formIntersection(ids)
            self.phase = .ready
        }
    }

    var findings: [Finding] { report?.findings ?? [] }

    /// Things Dustpan can move come first, then things for other tools, then locked ones.
    func findings(in category: RuleCategory) -> [Finding] {
        func rank(_ finding: Finding) -> Int { finding.locked ? 2 : finding.isCleanable ? 0 : 1 }
        return findings.filter { $0.rule.category == category }.sorted { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : a.bytes > b.bytes
        }
    }

    func isOpen(_ finding: Finding) -> Bool {
        toggledOpen.contains(finding.id) != (finding.rule.safety == .review)
    }

    func toggleOpen(_ finding: Finding) {
        if toggledOpen.contains(finding.id) { toggledOpen.remove(finding.id) } else { toggledOpen.insert(finding.id) }
    }

    func bytes(in category: RuleCategory) -> Int64 {
        findings(in: category).reduce(0) { $0 + $1.bytes }
    }

    var categoriesWithFindings: [RuleCategory] {
        RuleCategory.allCases.filter { !findings(in: $0).isEmpty }
    }

    // MARK: Selection

    func isSelectable(_ finding: Finding) -> Bool {
        finding.isCleanable && !finding.locked
    }

    func state(of finding: Finding) -> NSControl.StateValue {
        let selected = finding.targets.filter { selection.contains($0.id) }.count
        if selected == 0 { return .off }
        return selected == finding.targets.count ? .on : .mixed
    }

    func toggle(_ finding: Finding) {
        let ids = finding.targets.map(\.id)
        if state(of: finding) == .on {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    func toggle(_ target: Target) {
        if selection.contains(target.id) {
            selection.remove(target.id)
        } else {
            selection.insert(target.id)
        }
    }

    func select(_ safety: Safety, in category: RuleCategory? = nil) {
        for finding in findings where isSelectable(finding) && finding.rule.safety == safety {
            if let category, finding.rule.category != category { continue }
            selection.formUnion(finding.targets.map(\.id))
        }
    }

    func cleanableBytes(_ safety: Safety, in category: RuleCategory? = nil) -> Int64 {
        findings.filter { isSelectable($0) && $0.rule.safety == safety && (category == nil || $0.rule.category == category) }
            .reduce(0) { $0 + $1.bytes }
    }

    /// Selected targets, grouped by the finding they belong to.
    var selectedGroups: [(finding: Finding, targets: [Target])] {
        findings.filter(isSelectable).compactMap { finding -> (finding: Finding, targets: [Target])? in
            let targets = finding.targets.filter { selection.contains($0.id) }
            return targets.isEmpty ? nil : (finding, targets)
        }
        .sorted { $0.targets.reduce(0) { $0 + $1.bytes } > $1.targets.reduce(0) { $0 + $1.bytes } }
    }

    var selectedTargets: [Target] { selectedGroups.flatMap(\.targets) }
    var selectedBytes: Int64 { selectedTargets.reduce(0) { $0 + $1.bytes } }

    /// Apps the selected rules ask you to quit, with whether each seems to be running.
    var appsToQuit: [(name: String, running: Bool)] {
        let names = Set(selectedGroups.flatMap(\.finding.rule.quitFirst)).sorted()
        let running = NSWorkspace.shared.runningApplications.compactMap(\.localizedName).map { $0.lowercased() }
        return names.map { name in
            let key = name.lowercased().replacingOccurrences(of: "vs code", with: "code")
            return (name, running.contains(key))
        }
    }

    // MARK: Cleaning

    func clean() async {
        let targets = selectedTargets
        guard !targets.isEmpty else { return }
        phase = .cleaning
        let result = await Task.detached(priority: .userInitiated) { Cleaner().clean(targets) }.value
        apply(result)
        self.result = result
        sheet = .result
        phase = .ready
    }

    func finishSweep() {
        sheet = nil
        result = nil
    }

    /// Finder can ask for an administrator password where Dustpan can't, e.g. for apps installed by root.
    func retryWithFinder() async {
        guard var result, !result.failures.isEmpty else { return }
        let targets = result.failures.filter(\.needsAdmin).map(\.target)
        phase = .cleaning
        let outcome = await Task.detached(priority: .userInitiated) { FinderTrash.move(targets) }.value
        let movedIDs = Set(outcome.moved.map(\.id))
        result.moved += outcome.moved
        result.failures = result.failures.filter { !movedIDs.contains($0.target.id) }
        apply(outcome)
        self.result = result
        phase = .ready
    }

    private func apply(_ outcome: CleanResult) {
        sweptBytes += outcome.movedBytes
        guard let report else { return }
        let moved = Set(outcome.moved.map(\.id))
        selection.subtract(moved)
        let remaining = report.findings.compactMap { finding -> Finding? in
            var finding = finding
            finding.targets.removeAll { moved.contains($0.id) }
            return finding.targets.isEmpty && !finding.locked ? nil : finding
        }
        self.report = ScanReport(
            findings: remaining,
            disk: SystemInfo.disk() ?? report.disk,
            hasFullDiskAccess: report.hasFullDiskAccess,
            trashBytes: report.trashBytes.map { $0 + outcome.movedBytes },
            startedAt: report.startedAt,
            duration: report.duration
        )
        if case .category(let category) = sidebar, findings(in: category).isEmpty {
            sidebar = .overview
        }
    }
}
