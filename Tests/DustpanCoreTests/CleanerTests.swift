import Foundation
import Testing
@testable import DustpanCore

@Suite("Cleaning")
struct CleanerTests {
    @Test("Moves what's allowed and refuses what isn't")
    func guarded() {
        let sandbox = Sandbox()
        let cache = sandbox.folder("home/.cache/uv")
        let documents = sandbox.folder("home/Documents")
        let trash = FakeTrash()
        let cleaner = Cleaner(safety: SafetyGuard(home: sandbox.url("home")), trashCan: trash)

        let result = cleaner.clean([target(cache, bytes: 5), target(documents, bytes: 7)])
        #expect(trash.moved == [cache])
        #expect(result.movedBytes == 5)
        #expect(result.failures.map(\.target.url) == [documents])
    }

    @Test("A folder and something inside it move once")
    func nested() {
        let sandbox = Sandbox()
        let parent = sandbox.folder("home/Library/Caches/Google")
        let child = sandbox.folder("home/Library/Caches/Google/Chrome")
        let trash = FakeTrash()
        let cleaner = Cleaner(safety: SafetyGuard(home: sandbox.url("home")), trashCan: trash)
        _ = cleaner.clean([target(child), target(parent)])
        #expect(trash.moved == [parent])
    }

    @Test("Things that vanished in the meantime are skipped quietly")
    func vanished() {
        let sandbox = Sandbox()
        let trash = FakeTrash()
        let cleaner = Cleaner(safety: SafetyGuard(home: sandbox.url("home")), trashCan: trash)
        let result = cleaner.clean([target(sandbox.url("home/.cache/gone"))])
        #expect(trash.moved.isEmpty)
        #expect(result.failures.isEmpty)
    }

    @Test("Permission errors are flagged as needing an admin")
    func permission() {
        let sandbox = Sandbox()
        let cache = sandbox.folder("home/.cache/locked")
        let trash = FakeTrash()
        trash.failWith = CocoaError(.fileWriteNoPermission)
        let cleaner = Cleaner(safety: SafetyGuard(home: sandbox.url("home")), trashCan: trash)
        let result = cleaner.clean([target(cache)])
        #expect(result.failures.first?.needsAdmin == true)
    }
}

@Suite("Formatting")
struct FormatTests {
    @Test("Decimal units that never read 1000", arguments: [
        (999, "999 bytes"), (1000, "1.0 KB"), (123_456_789, "123 MB"), (999_600_000, "1.0 GB"),
        (11_400_000_000, "11.4 GB"), (99_960_000, "100 MB"),
    ] as [(Int64, String)])
    func bytes(_ count: Int64, _ expected: String) {
        #expect(Format.bytes(count, language: .english) == expected)
    }

    @Test("Relative dates")
    func relative() {
        let now = Date()
        func relative(_ days: Double) -> String { Format.relative(now.addingTimeInterval(-86_400 * days), now: now, language: .english) }
        #expect(relative(0) == "today")
        #expect(relative(1.5) == "yesterday")
        #expect(relative(21) == "3 weeks ago")
        #expect(relative(400) == "a year ago")
    }
}
