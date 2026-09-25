import Foundation
import Testing
@testable import DustpanCore

@Suite("Review fixes")
struct FixesTests {
    @Test("A nested target moves with its folder, even when a sibling sorts between them")
    func nestedWithSibling() {
        let paths = ["/Users/tester/a/b/c", "/Users/tester/a/b-c", "/Users/tester/a/b"]
        let kept = Cleaner.withoutNestedTargets(paths.map { target(URL(fileURLWithPath: $0)) })
        #expect(Set(kept.map(\.url.path)) == ["/Users/tester/a/b", "/Users/tester/a/b-c"])
    }

    @Test("Caches belong to the open app they're named after, and projects never do")
    func owners() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let apps = [
            RunningApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
            RunningApp(name: "Google Chrome", bundleID: "com.google.Chrome"),
            RunningApp(name: "Code", bundleID: "com.microsoft.VSCode"),
            RunningApp(name: "Claude", bundleID: "com.anthropic.claudefordesktop"),
        ]
        func owner(_ path: String) -> String? {
            target(URL(fileURLWithPath: "/Users/tester/" + path)).owner(among: apps, home: home)?.name
        }
        #expect(owner("Library/Caches/com.tinyspeck.slackmacgap") == "Slack")
        #expect(owner("Library/Caches/com.anthropic.claudefordesktop.ShipIt") == "Claude")
        #expect(owner("Library/Caches/Google/Chrome") == "Google Chrome")
        #expect(owner("Library/Application Support/Code/CachedData") == "Code")
        #expect(owner("Library/Application Support/Claude/Cache") == "Claude")
        #expect(owner("Code/my-app/node_modules") == nil)
        #expect(owner("Library/Developer/Xcode/DerivedData") == nil)
        #expect(owner("Library/Caches/pip") == nil)
    }

    @Test("A Desktop that iCloud syncs through a symlink counts as cloud storage")
    func iCloudDesktop() throws {
        let sandbox = Sandbox()
        let cloudDesktop = sandbox.folder("home/Library/Mobile Documents/com~apple~CloudDocs/Desktop")
        try FileManager.default.createSymbolicLink(at: sandbox.url("home/Desktop"), withDestinationURL: cloudDesktop)
        sandbox.folder("home/Library/Mobile Documents/com~apple~CloudDocs/Desktop/app/node_modules")
        let safety = SafetyGuard(home: sandbox.url("home"))
        let modules = sandbox.url("home/Desktop/app/node_modules")
        #expect(safety.isInCloudStorage(modules))
        #expect(safety.refusal(for: modules) != nil)
        #expect(!safety.isInCloudStorage(sandbox.folder("home/Code/app/node_modules")))
    }

    @Test("Build folders in a synced folder are left out of the scan")
    func cloudProjectsSkipped() async throws {
        let sandbox = Sandbox()
        let cloudDesktop = sandbox.folder("home/Library/Mobile Documents/com~apple~CloudDocs/Desktop")
        try FileManager.default.createSymbolicLink(at: sandbox.url("home/Desktop"), withDestinationURL: cloudDesktop)
        sandbox.file("home/Desktop/web/package.json")
        sandbox.file("home/Desktop/web/node_modules/pkg/index.js", bytes: 2_000_000)
        let rules = Catalog.rules.filter { $0.id == "node-modules" }
        let options = ScanOptions(home: sandbox.url("home"), projectRoots: [sandbox.url("home/Desktop")], minimumBytes: 1)
        let report = await Scanner(options: options, rules: rules).scan()
        #expect(report.findings.isEmpty)
    }

    @Test("A project root that is a symlink is followed")
    func symlinkedRoot() throws {
        let sandbox = Sandbox()
        let real = sandbox.folder("external/code")
        sandbox.file("external/code/app/package.json")
        sandbox.folder("external/code/app/node_modules")
        try FileManager.default.createSymbolicLink(at: sandbox.url("home-code"), withDestinationURL: real)
        let kinds: [(ruleID: String, kind: ArtifactKind)] = [("node", ArtifactKind(folders: ["node_modules"], markers: ["package.json"]))]
        let hits = ProjectScanner(roots: [sandbox.url("home-code")], kinds: kinds).find()
        #expect(hits.count == 1)
    }

    @Test("Go's read-only module cache is left to go clean")
    func goModuleCache() {
        #expect(Catalog.rule(id: "go-module-cache")?.cleanup == .command("go clean -modcache"))
    }
}
