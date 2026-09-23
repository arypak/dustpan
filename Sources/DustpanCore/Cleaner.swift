import Foundation

/// Somewhere to put things. The real one is the macOS Trash; tests use a fake.
public protocol TrashCan: Sendable {
    func moveToTrash(_ url: URL) throws
}

public struct SystemTrash: TrashCan {
    public init() {}

    public func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

public struct CleanResult: Sendable {
    public struct Failure: Sendable, Hashable {
        public let target: Target
        public let reason: String
        /// The item belongs to another user (often root), so only Finder with an admin password can move it.
        public let needsAdmin: Bool

        public init(target: Target, reason: String, needsAdmin: Bool) {
            self.target = target
            self.reason = reason
            self.needsAdmin = needsAdmin
        }
    }

    public var moved: [Target] = []
    public var failures: [Failure] = []

    public init() {}

    public var movedBytes: Int64 { moved.reduce(0) { $0 + $1.bytes } }
}

/// Moves targets to the Trash. Dustpan never deletes anything itself: emptying the Trash is up to you.
public struct Cleaner: Sendable {
    public let safety: SafetyGuard
    public let trashCan: any TrashCan

    public init(safety: SafetyGuard = SafetyGuard(), trashCan: any TrashCan = SystemTrash()) {
        self.safety = safety
        self.trashCan = trashCan
    }

    public func clean(_ targets: [Target], progress: (Int, Int) -> Void = { _, _ in }) -> CleanResult {
        var result = CleanResult()
        let batch = Self.withoutNestedTargets(targets)
        for (index, target) in batch.enumerated() {
            progress(index, batch.count)
            if let reason = safety.refusal(for: target.url) {
                result.failures.append(.init(target: target, reason: reason, needsAdmin: false))
                continue
            }
            guard FileSystem.exists(target.url.path) else {
                // Already gone (an app cleaned up after itself). Nothing to do, nothing freed.
                continue
            }
            do {
                try trashCan.moveToTrash(target.url)
                result.moved.append(target)
            } catch {
                result.failures.append(.init(
                    target: target,
                    reason: Self.describe(error),
                    needsAdmin: Self.isPermissionError(error)
                ))
            }
        }
        progress(batch.count, batch.count)
        return result
    }

    /// When a folder and something inside it are both selected, trashing the folder covers both.
    static func withoutNestedTargets(_ targets: [Target]) -> [Target] {
        let sorted = targets.sorted { $0.url.path < $1.url.path }
        var kept: [Target] = []
        for target in sorted {
            if let last = kept.last, target.url.path == last.url.path || target.url.path.hasPrefix(last.url.path + "/") {
                continue
            }
            kept.append(target)
        }
        return kept
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(nsError.code) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           [Int(EPERM), Int(EACCES)].contains(underlying.code) {
            return true
        }
        return false
    }

    static func describe(_ error: Error) -> String {
        if isPermissionError(error) {
            return L("macOS didn't allow it. It may belong to the system or another user; try Finder.")
        }
        return (error as NSError).localizedDescription
    }
}
