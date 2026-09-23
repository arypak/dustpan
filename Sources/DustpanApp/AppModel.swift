import AppKit
import DustpanCore
import Observation

typealias RuleCategory = DustpanCore.Category

enum SidebarItem: Hashable {
    case overview
    case category(RuleCategory)
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("System")
        case .light: L("Light")
        case .dark: L("Dark")
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum LanguagePreference: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case turkish = "tr"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("System")
        case .english: Language.english.nativeName
        case .turkish: Language.turkish.nativeName
        }
    }

    var language: Language {
        Language(rawValue: rawValue) ?? .system
    }
}

/// Something the user has to agree to see first.
enum Reveal: Equatable {
    case category(RuleCategory)
    case finding(String)
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
    /// Findings the user opened or closed, relative to how they start.
    var toggledOpen: Set<String> = []
    private(set) var sidebar: SidebarItem? = .overview
    var sheet: Sheet?
    var result: CleanResult?
    /// Bytes this session has moved to the Trash.
    private(set) var sweptBytes: Int64 = 0

    /// Review items stay out of sight until the user agrees to see them, once per launch.
    private(set) var revealedFindings: Set<String> = []
    private(set) var revealedCategories: Set<RuleCategory> = []
    var pendingReveal: Reveal?

    var projectRoots: [URL] {
        didSet { UserDefaults.standard.set(projectRoots.map(\.path), forKey: "projectRoots") }
    }

    var appearance: AppearancePreference {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

    var languagePreference: LanguagePreference {
        didSet {
            UserDefaults.standard.set(languagePreference.rawValue, forKey: "language")
            // AppKit's own menus follow AppleLanguages, which it reads at launch.
            if languagePreference == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([languagePreference.rawValue], forKey: "AppleLanguages")
            }
            applyLanguage()
        }
    }

    /// The language on screen. Views use it as an identity, so changing it redraws everything.
    private(set) var language: Language = .english

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        projectRoots = defaults.stringArray(forKey: "projectRoots")?.map { URL(fileURLWithPath: $0) }
            ?? ProjectScanner.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser)
        appearance = AppearancePreference(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        languagePreference = LanguagePreference(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        applyLanguage()
    }

    private func applyLanguage() {
        // DUSTPAN_LANG lets screenshots use a fixed language without touching the saved choice.
        let forced = ProcessInfo.processInfo.environment["DUSTPAN_LANG"].flatMap(Language.init(rawValue:))
        Localization.language = forced ?? languagePreference.language
        language = Localization.language
    }

    func applyAppearance() {
        NSApp?.appearance = appearance.appearance
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

    func bytes(in category: RuleCategory) -> Int64 {
        findings(in: category).reduce(0) { $0 + $1.bytes }
    }

    var categoriesWithFindings: [RuleCategory] {
        RuleCategory.allCases.filter { !findings(in: $0).isEmpty }
    }

    // MARK: Risky things

    /// Review findings can be apps, VMs, backups or projects someone still uses.
    func isRisky(_ finding: Finding) -> Bool {
        finding.rule.safety == .review && !finding.locked
    }

    func isRevealed(_ finding: Finding) -> Bool {
        !isRisky(finding) || revealedFindings.contains(finding.id) || revealedCategories.contains(finding.rule.category)
    }

    /// A category made only of risky findings asks before it opens at all.
    func isRisky(_ category: RuleCategory) -> Bool {
        let visible = findings(in: category).filter { !$0.locked }
        return !visible.isEmpty && visible.allSatisfy { isRisky($0) }
    }

    func asksBeforeOpening(_ category: RuleCategory) -> Bool {
        isRisky(category) && !revealedCategories.contains(category)
    }

    func navigate(to item: SidebarItem?) {
        guard let item else { return }
        if case .category(let category) = item, asksBeforeOpening(category) {
            pendingReveal = .category(category)
            // The list already highlighted the clicked row; touch the selection so it snaps back
            // to the page that's actually showing.
            let showing = sidebar
            sidebar = nil
            sidebar = showing
            return
        }
        sidebar = item
    }

    func requestReveal(_ finding: Finding) {
        pendingReveal = .finding(finding.id)
    }

    func confirmReveal() {
        switch pendingReveal {
        case .category(let category):
            revealedCategories.insert(category)
            sidebar = .category(category)
        case .finding(let id):
            revealedFindings.insert(id)
        case nil:
            break
        }
        pendingReveal = nil
    }

    /// Risky findings open once revealed; everything else starts closed.
    func isOpen(_ finding: Finding) -> Bool {
        guard isRevealed(finding) else { return false }
        return toggledOpen.contains(finding.id) != isRisky(finding)
    }

    func toggleOpen(_ finding: Finding) {
        if toggledOpen.contains(finding.id) { toggledOpen.remove(finding.id) } else { toggledOpen.insert(finding.id) }
    }

    // MARK: Selection

    func isSelectable(_ finding: Finding) -> Bool {
        finding.isCleanable && !finding.locked && isRevealed(finding)
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

    /// What Dustpan could move for a safety level, revealed or not.
    func cleanableBytes(_ safety: Safety, in category: RuleCategory? = nil) -> Int64 {
        findings.filter { $0.isCleanable && !$0.locked && $0.rule.safety == safety && (category == nil || $0.rule.category == category) }
            .reduce(0) { $0 + $1.bytes }
    }

    /// Selected targets, grouped by the finding they belong to, biggest first.
    var selectedGroups: [(finding: Finding, targets: [Target])] {
        findings.filter { isSelectable($0) }.compactMap { finding -> (finding: Finding, targets: [Target])? in
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

    // MARK: Screenshots

    /// Lets the snapshot tool visit pages without going through the confirmation.
    func showForSnapshot(_ item: SidebarItem) {
        sidebar = item
    }
}
