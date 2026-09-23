import Foundation
@testable import DustpanCore

/// A throwaway folder that stands in for a home directory. Removed when the test ends.
final class Sandbox {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dustpan-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    @discardableResult
    func folder(_ path: String) -> URL {
        let url = url(path)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func file(_ path: String, bytes: Int = 1, modified: Date? = nil) -> URL {
        let url = url(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(repeating: 0x2A, count: bytes).write(to: url)
        if let modified {
            try! FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }
}

/// Records what would have gone to the Trash instead of moving it.
final class FakeTrash: TrashCan, @unchecked Sendable {
    private let lock = NSLock()
    private var _moved: [URL] = []
    var failWith: Error?

    var moved: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _moved
    }

    func moveToTrash(_ url: URL) throws {
        if let failWith { throw failWith }
        lock.lock(); defer { lock.unlock() }
        _moved.append(url)
    }
}

func target(_ url: URL, bytes: Int64 = 1) -> Target {
    Target(url: url, bytes: bytes, label: url.lastPathComponent)
}
