import Foundation

public struct ScanOptions: Sendable {
    public var home: URL
    /// Where to look for build output. Defaults to the usual code folders in your home.
    public var projectRoots: [URL]
    /// Targets smaller than this are left out of the report.
    public var minimumBytes: Int64
    /// Apps smaller than this aren't listed.
    public var largeAppBytes: Int64
    /// Only run these rules; `nil` runs all of them.
    public var ruleIDs: Set<String>?
    /// How many folders to measure at once.
    public var concurrency: Int

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        projectRoots: [URL]? = nil,
        minimumBytes: Int64 = 1_000_000,
        largeAppBytes: Int64 = 500_000_000,
        ruleIDs: Set<String>? = nil,
        concurrency: Int = 6
    ) {
        self.home = home
        self.projectRoots = projectRoots ?? ProjectScanner.defaultRoots(home: home)
        self.minimumBytes = minimumBytes
        self.largeAppBytes = largeAppBytes
        self.ruleIDs = ruleIDs
        self.concurrency = max(1, concurrency)
    }
}

public struct ScanProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let current: String

    public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}

public struct Scanner: Sendable {
    public var options: ScanOptions
    public var rules: [Rule]

    public init(options: ScanOptions = ScanOptions(), rules: [Rule] = Catalog.rules) {
        self.options = options
        self.rules = rules
    }

    /// Something to measure, or something whose size is already known.
    struct Job: Sendable {
        let rule: Rule
        let url: URL
        let label: String
        var note: TargetNote?
        var modified: Date?
        var command: String?
        var knownBytes: Int64?
        var minimumBytes: Int64
    }

    public func scan(progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async -> ScanReport {
        let started = Date()
        let home = options.home
        let fullDiskAccess = SystemInfo.hasFullDiskAccess(home: home)
        let active = rules.filter { options.ruleIDs?.contains($0.id) ?? true }
        let resolver = PathResolver(home: home)

        progress(ScanProgress(completed: 0, total: 0, current: L("Looking around")))

        // Rules the scan can't see into without Full Disk Access. Only report the ones that apply here.
        let lockedRules = fullDiskAccess ? [] : active.filter { rule in
            rule.needsFullDiskAccess && rule.locations.contains { resolver.isPresent($0.pattern) }
        }
        let visible = active.filter { !($0.needsFullDiskAccess && !fullDiskAccess) }

        // Slower discoveries run alongside the path rules.
        async let projectJobs = projectJobs(for: visible)
        async let applicationJobs = applicationJobs(for: visible)
        async let simulatorJobs = simulatorJobs(for: visible)
        var jobs = locationJobs(for: visible, resolver: resolver)
        jobs += await projectJobs
        jobs += await applicationJobs
        jobs += await simulatorJobs

        let sizes = await measure(jobs, progress: progress)

        var targets: [String: [Target]] = [:]
        for (job, size) in zip(jobs, sizes) {
            let bytes = job.knownBytes ?? size
            guard bytes >= job.minimumBytes else { continue }
            targets[job.rule.id, default: []].append(Target(
                url: job.url, bytes: bytes, modified: job.modified,
                label: job.label, note: job.note, command: job.command
            ))
        }

        var findings = active.compactMap { rule -> Finding? in
            if lockedRules.contains(rule) { return Finding(rule: rule, targets: [], locked: true) }
            guard let found = targets[rule.id], !found.isEmpty else { return nil }
            return Finding(rule: rule, targets: found.sorted { $0.bytes > $1.bytes })
        }
        let order = Dictionary(uniqueKeysWithValues: Category.allCases.enumerated().map { ($1, $0) })
        findings.sort { a, b in
            a.rule.category != b.rule.category ? order[a.rule.category]! < order[b.rule.category]! : a.bytes > b.bytes
        }

        return ScanReport(
            findings: findings,
            disk: SystemInfo.disk(home: home),
            hasFullDiskAccess: fullDiskAccess,
            trashBytes: fullDiskAccess ? SystemInfo.trashSize(home: home) : nil,
            startedAt: started,
            duration: Date().timeIntervalSince(started)
        )
    }

    // MARK: - Discovery

    func locationJobs(for rules: [Rule], resolver: PathResolver) -> [Job] {
        var jobs: [Job] = []
        var claimed: [String] = []
        // Specific rules claim their paths first; catch-alls get what's left.
        let ordered = rules.filter { !$0.isCatchAll } + rules.filter(\.isCatchAll)
        for rule in ordered {
            guard rule.discovery == .locations || rule.discovery == .deviceBackups else { continue }
            for location in rule.locations {
                for candidate in resolver.resolve(location) {
                    let paths = rule.isCatchAll
                        ? Self.split(candidate.url.path, around: claimed)
                        : Self.isClaimed(candidate.url.path, by: claimed) ? [] : [candidate.url.path]
                    for path in paths {
                        claimed.append(path)
                        let url = URL(fileURLWithPath: path)
                        var modified = candidate.modified
                        if path != candidate.url.path, case .found(let entry) = FileSystem.lookup(path) {
                            modified = entry.modified
                        }
                        var job = Job(
                            rule: rule, url: url,
                            label: resolver.label(for: url, location: location),
                            modified: modified,
                            minimumBytes: options.minimumBytes
                        )
                        if candidate.isChild {
                            job.note = .modified(modified)
                        }
                        if rule.discovery == .deviceBackups, let backup = Discoverers.backupInfo(url) {
                            job = Job(
                                rule: rule, url: url, label: backup.name,
                                note: backup.date.map { .backedUp($0) },
                                modified: backup.date, minimumBytes: options.minimumBytes
                            )
                        }
                        jobs.append(job)
                    }
                }
            }
        }
        return jobs
    }

    func projectJobs(for rules: [Rule]) async -> [Job] {
        let kinds: [(ruleID: String, kind: ArtifactKind)] = rules.compactMap { rule in
            if case .projects(let kind) = rule.discovery { (rule.id, kind) } else { nil }
        }
        guard !kinds.isEmpty, !options.projectRoots.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        let hits = ProjectScanner(roots: options.projectRoots, kinds: kinds).find { Task.isCancelled }
        return hits.compactMap { hit in
            guard let rule = byID[hit.ruleID] else { return nil }
            let project = hit.project
            let inside = hit.url.path.dropFirst(project.path.count + 1)
            return Job(
                rule: rule, url: hit.url,
                label: project.lastPathComponent + "/" + inside,
                note: .touched(hit.modified, in: Format.path(project.deletingLastPathComponent(), home: options.home)),
                modified: hit.modified,
                minimumBytes: options.minimumBytes
            )
        }
    }

    func applicationJobs(for rules: [Rule]) async -> [Job] {
        guard let rule = rules.first(where: { $0.discovery == .applications }) else { return [] }
        return Discoverers.applicationBundles(home: options.home).map { url in
            let opened = Discoverers.lastOpened(url)
            return Job(
                rule: rule, url: url,
                label: url.deletingPathExtension().lastPathComponent,
                note: .lastOpened(opened),
                modified: opened,
                minimumBytes: options.largeAppBytes
            )
        }
    }

    func simulatorJobs(for rules: [Rule]) async -> [Job] {
        var jobs: [Job] = []
        if let rule = rules.first(where: { $0.discovery == .simulatorRuntimes }) {
            jobs += Discoverers.simulatorRuntimes().map { runtime in
                Job(
                    rule: rule, url: URL(fileURLWithPath: runtime.path),
                    label: runtime.name,
                    note: runtime.lastUsed.map { .lastUsed($0) },
                    modified: runtime.lastUsed,
                    command: "xcrun simctl runtime delete \(runtime.identifier)",
                    knownBytes: runtime.bytes,
                    minimumBytes: options.minimumBytes
                )
            }
        }
        if let rule = rules.first(where: { $0.discovery == .unavailableSimulators }) {
            jobs += Discoverers.unavailableSimulators(home: options.home).map { device in
                Job(rule: rule, url: device.folder, label: "\(device.name) · \(device.runtime)", minimumBytes: 1)
            }
        }
        return jobs
    }

    // MARK: - Measuring

    /// Sizes in the same order as `jobs`, measuring a few folders at a time.
    func measure(_ jobs: [Job], progress: @escaping @Sendable (ScanProgress) -> Void) async -> [Int64] {
        var sizes = [Int64](repeating: 0, count: jobs.count)
        await withTaskGroup(of: (Int, Int64).self) { group in
            var next = 0
            var done = 0
            while next < min(options.concurrency, jobs.count) {
                let index = next
                group.addTask { (index, Self.size(of: jobs[index])) }
                next += 1
            }
            while let (index, size) = await group.next() {
                sizes[index] = size
                done += 1
                progress(ScanProgress(completed: done, total: jobs.count, current: jobs[index].rule.name))
                if next < jobs.count && !Task.isCancelled {
                    let index = next
                    group.addTask { (index, Self.size(of: jobs[index])) }
                    next += 1
                }
            }
        }
        return sizes
    }

    static func size(of job: Job) -> Int64 {
        if let known = job.knownBytes { return known }
        return DirectorySizer.measure(job.url) { Task.isCancelled }.bytes
    }

    // MARK: - Claims

    static func isClaimed(_ path: String, by claimed: [String]) -> Bool {
        claimed.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// `path`, minus anything already claimed. A folder that contains a claimed path
    /// is replaced by its other children, so nothing is counted twice.
    static func split(_ path: String, around claimed: [String]) -> [String] {
        if isClaimed(path, by: claimed) { return [] }
        let inside = claimed.filter { $0.hasPrefix(path + "/") }
        if inside.isEmpty { return [path] }
        let names = (FileSystem.list(path) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        return names.flatMap { split(path + "/" + $0, around: inside) }
    }
}

extension PathResolver {
    /// Whether anything at `pattern` exists, even if macOS won't let us look inside.
    func isPresent(_ pattern: String) -> Bool {
        var paths = ["/"]
        for component in expandTilde(pattern).split(separator: "/").map(String.init) {
            var next: [String] = []
            for base in paths {
                let prefix = base == "/" ? "/" : base + "/"
                if component.contains("*") {
                    guard let names = FileSystem.list(base) else { return true }
                    next += names.filter { !$0.hasPrefix(".") && FileSystem.matches($0, component) }.map { prefix + $0 }
                } else {
                    switch FileSystem.lookup(prefix + component) {
                    case .found: next.append(prefix + component)
                    case .denied: return true
                    case .missing: break
                    }
                }
            }
            paths = next
            if paths.isEmpty { return false }
        }
        return true
    }

    /// What to call a target: children by their name, wildcard matches by what the wildcard matched.
    func label(for url: URL, location: Location) -> String {
        let pattern = expandTilde(location.pattern)
        let literal = pattern.split(separator: "/", omittingEmptySubsequences: false)
            .prefix { !$0.contains("*") }
            .joined(separator: "/")
        let base: String
        switch location.mode {
        case .children:
            // Children of a wildcard folder are named relative to the folder they were found in.
            base = pattern.contains("*") ? literal : pattern
        case .item:
            guard pattern.contains("*") else { return Format.path(url, home: home) }
            base = literal
        }
        let path = url.path
        return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : url.lastPathComponent
    }
}
