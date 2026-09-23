import Foundation

/// How sure Dustpan is that sweeping something away is harmless.
public enum Safety: String, Codable, Sendable, CaseIterable, Comparable {
    /// Regenerates on its own. Nothing you'd miss.
    case safe
    /// Comes back, but costs a re-download or a rebuild.
    case caution
    /// Your data, or a tool you may still use. Look before you sweep.
    case review

    public var title: String {
        switch self {
        case .safe: L("Safe")
        case .caution: L("Caution")
        case .review: L("Review")
        }
    }

    public var explanation: String {
        switch self {
        case .safe: L("Regenerates on its own")
        case .caution: L("Comes back after a re-download or rebuild")
        case .review: L("Your data or tools you may still use")
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (lhs: Safety, rhs: Safety) -> Bool { lhs.rank < rhs.rank }
}

public enum Category: String, Codable, Sendable, CaseIterable, Identifiable {
    case caches
    case xcode
    case packages
    case projects
    case toolchains
    case virtualization
    case aiModels
    case applications
    case files

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .caches: L("App Caches")
        case .xcode: L("Xcode & Simulators")
        case .packages: L("Package Managers")
        case .projects: L("Build Artifacts")
        case .toolchains: L("SDKs & Toolchains")
        case .virtualization: L("VMs & Containers")
        case .aiModels: L("AI Models")
        case .applications: L("Large Apps")
        case .files: L("Downloads & Backups")
        }
    }

    /// SF Symbol used by the app.
    public var symbol: String {
        switch self {
        case .caches: "archivebox"
        case .xcode: "hammer"
        case .packages: "shippingbox"
        case .projects: "folder.badge.gearshape"
        case .toolchains: "wrench.and.screwdriver"
        case .virtualization: "cube.transparent"
        case .aiModels: "cpu"
        case .applications: "app.badge"
        case .files: "arrow.down.doc"
        }
    }
}

/// Where a rule looks. Patterns start with `~` or `/` and may use `*` wildcards
/// in any path component, e.g. `~/Library/Application Support/*/GPUCache`.
public struct Location: Sendable, Hashable {
    public enum Mode: Sendable, Hashable {
        /// The matched path itself is one target.
        case item
        /// Every child of the matched directory is its own target.
        case children
    }

    public var pattern: String
    public var mode: Mode
    /// Names to leave alone, as `fnmatch` patterns. Applied to wildcard matches and children.
    public var excluding: [String]
    /// Children only: keep entries whose name matches one of these `fnmatch` patterns.
    public var matching: [String]
    /// Children only: keep entries that haven't been modified for this many days.
    public var olderThanDays: Int?

    public static func item(_ pattern: String, excluding: [String] = []) -> Location {
        Location(pattern: pattern, mode: .item, excluding: excluding, matching: [], olderThanDays: nil)
    }

    public static func children(
        _ pattern: String,
        excluding: [String] = [],
        matching: [String] = [],
        olderThanDays: Int? = nil
    ) -> Location {
        Location(pattern: pattern, mode: .children, excluding: excluding, matching: matching, olderThanDays: olderThanDays)
    }
}

/// What Dustpan does with a finding.
public enum Cleanup: Sendable, Hashable {
    /// Dustpan moves the targets to the Trash.
    case trash
    /// Dustpan only reports. The tool that owns the data should clean it: run this command.
    case command(String)
    /// Dustpan only reports. Clean it from the owning app: follow these steps.
    case manual(String)

    public var isTrash: Bool {
        if case .trash = self { true } else { false }
    }

    /// Manual steps, translated. Commands are never translated.
    public var localizedSteps: String? {
        englishSteps.map { L($0) }
    }

    public var englishSteps: String? {
        if case .manual(let steps) = self { steps } else { nil }
    }
}

/// How the scanner finds a rule's targets.
public enum Discovery: Sendable, Hashable {
    /// Resolve the rule's `locations`.
    case locations
    /// Look for build output folders inside project folders.
    case projects(ArtifactKind)
    /// Big `.app` bundles in /Applications and ~/Applications.
    case applications
    /// Simulator runtimes, as listed by `xcrun simctl runtime list`.
    case simulatorRuntimes
    /// Simulators whose runtime is gone, as listed by `xcrun simctl list devices unavailable`.
    case unavailableSimulators
    /// Local iPhone/iPad backups, labelled with the device name.
    case deviceBackups
}

/// A kind of throwaway folder inside a project, recognised by a marker file next to it.
public struct ArtifactKind: Sendable, Hashable {
    /// Folder names to look for, e.g. `node_modules`.
    public var folders: Set<String>
    /// At least one of these must sit next to the folder, e.g. `package.json`.
    public var markers: [String]
    /// A file that must exist inside the folder instead of a marker next to it, e.g. `pyvenv.cfg`.
    public var innerMarker: String?

    public init(folders: Set<String>, markers: [String] = [], innerMarker: String? = nil) {
        self.folders = folders
        self.markers = markers
        self.innerMarker = innerMarker
    }
}

public struct Rule: Sendable, Identifiable, Hashable {
    public let id: String
    public let category: Category
    public let safety: Safety
    public let locations: [Location]
    public let discovery: Discovery
    public let cleanup: Cleanup
    /// Apps to quit before cleaning. App names aren't translated.
    public let quitFirst: [String]
    /// Catch-all rules skip anything another rule already claimed.
    public let isCatchAll: Bool

    /// The English source texts; the properties below translate them.
    public let englishName: String
    public let englishSummary: String
    public let englishAftermath: String
    public let englishNote: String?

    public var name: String { L(englishName) }
    /// What this is, in one sentence.
    public var summary: String { L(englishSummary) }
    /// What happens after it's gone.
    public var aftermath: String { L(englishAftermath) }
    /// Anything else worth knowing, e.g. why the freed space may be lower than shown.
    public var note: String? { englishNote.map { L($0) } }

    public init(
        _ id: String,
        _ name: String,
        _ category: Category,
        _ safety: Safety,
        summary: String,
        aftermath: String,
        locations: [Location] = [],
        discovery: Discovery = .locations,
        cleanup: Cleanup = .trash,
        quitFirst: [String] = [],
        note: String? = nil,
        isCatchAll: Bool = false
    ) {
        self.id = id
        self.englishName = name
        self.category = category
        self.safety = safety
        self.englishSummary = summary
        self.englishAftermath = aftermath
        self.locations = locations
        self.discovery = discovery
        self.cleanup = cleanup
        self.quitFirst = quitFirst
        self.englishNote = note
        self.isCatchAll = isCatchAll
    }

    /// Folders macOS keeps private unless the app has Full Disk Access.
    static let protectedPrefixes = [
        "~/Library/Containers/", "~/Library/Group Containers/", "~/Library/Messages",
        "~/Library/Mail", "~/Library/Safari", "~/Library/Application Support/MobileSync", "~/.Trash",
    ]

    public var needsFullDiskAccess: Bool {
        locations.contains { location in
            Self.protectedPrefixes.contains { location.pattern.hasPrefix($0) }
        }
    }
}

/// What to say under a target's name. Kept as data so it can be shown in any language.
public enum TargetNote: Sendable, Hashable {
    case modified(Date)
    case lastOpened(Date?)
    case lastUsed(Date)
    case backedUp(Date)
    /// A build folder: where its project lives and when it last changed.
    case touched(Date, in: String)

    public var text: String {
        switch self {
        case .modified(let date): L("Modified %@", Format.relative(date))
        case .lastOpened(let date?): L("Last opened %@", Format.relative(date))
        case .lastOpened(nil): L("Last opened: unknown")
        case .lastUsed(let date): L("Last used %@", Format.relative(date))
        case .backedUp(let date): L("Backed up %@", Format.relative(date))
        case .touched(let date, let folder): L("%@ · touched %@", folder, Format.relative(date))
        }
    }
}

/// One concrete thing on disk that a rule found.
public struct Target: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let bytes: Int64
    public let modified: Date?
    /// Short display name, e.g. `node_modules` or `iOS 17.2`.
    public let label: String
    public let note: TargetNote?
    /// A per-target command, when the rule's cleanup differs per target.
    public let command: String?

    public init(url: URL, bytes: Int64, modified: Date? = nil, label: String, note: TargetNote? = nil, command: String? = nil) {
        self.url = url
        self.bytes = bytes
        self.modified = modified
        self.label = label
        self.note = note
        self.command = command
    }

    /// Secondary line, e.g. `~/Code · touched 3 weeks ago`, in the current language.
    public var detail: String? { note?.text }
}

/// A rule together with what it found on this Mac.
public struct Finding: Sendable, Identifiable, Hashable {
    public var id: String { rule.id }
    public let rule: Rule
    public var targets: [Target]
    /// The rule looks in places macOS only opens up with Full Disk Access, which Dustpan doesn't have.
    public var locked: Bool

    public init(rule: Rule, targets: [Target], locked: Bool = false) {
        self.rule = rule
        self.targets = targets
        self.locked = locked
    }

    public var bytes: Int64 { targets.reduce(0) { $0 + $1.bytes } }
    public var isCleanable: Bool { rule.cleanup.isTrash }
}

public struct DiskInfo: Sendable, Hashable {
    public let volumeName: String
    public let total: Int64
    /// Free right now.
    public let available: Int64
    /// Free once macOS purges what it can (old snapshots, caches it manages itself).
    public let availableIncludingPurgeable: Int64

    public init(volumeName: String, total: Int64, available: Int64, availableIncludingPurgeable: Int64) {
        self.volumeName = volumeName
        self.total = total
        self.available = available
        self.availableIncludingPurgeable = availableIncludingPurgeable
    }

    public var used: Int64 { total - available }
    public var purgeable: Int64 { max(0, availableIncludingPurgeable - available) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct ScanReport: Sendable {
    public let findings: [Finding]
    public let disk: DiskInfo?
    public let hasFullDiskAccess: Bool
    /// Size of the Trash, when Dustpan is allowed to look.
    public let trashBytes: Int64?
    public let startedAt: Date
    public let duration: TimeInterval

    public init(findings: [Finding], disk: DiskInfo?, hasFullDiskAccess: Bool, trashBytes: Int64?, startedAt: Date, duration: TimeInterval) {
        self.findings = findings
        self.disk = disk
        self.hasFullDiskAccess = hasFullDiskAccess
        self.trashBytes = trashBytes
        self.startedAt = startedAt
        self.duration = duration
    }

    /// Bytes Dustpan itself can move to the Trash, per safety level.
    public func cleanableBytes(_ safety: Safety) -> Int64 {
        findings.filter { $0.isCleanable && $0.rule.safety == safety }.reduce(0) { $0 + $1.bytes }
    }

    public var lockedFindings: [Finding] { findings.filter(\.locked) }
}
