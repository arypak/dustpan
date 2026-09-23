import Foundation
import Testing
@testable import DustpanCore

@Suite("Measuring")
struct SizerTests {
    @Test("Adds up what files use on disk")
    func sizes() {
        let sandbox = Sandbox()
        sandbox.file("cache/a", bytes: 40_000)
        sandbox.file("cache/nested/b", bytes: 60_000)
        let size = DirectorySizer.measure(sandbox.url("cache"))
        #expect(size.bytes >= 100_000)
        #expect(size.bytes < 140_000)
    }

    @Test("Counts hard links once, like du")
    func hardLinks() throws {
        let sandbox = Sandbox()
        let original = sandbox.file("store/pkg", bytes: 200_000)
        sandbox.folder("project")
        try FileManager.default.linkItem(at: original, to: sandbox.url("project/pkg"))
        let size = DirectorySizer.measure(sandbox.root)
        #expect(size.bytes < 300_000)
    }

    @Test("A missing path measures zero")
    func missing() {
        #expect(DirectorySizer.measure(URL(fileURLWithPath: "/nonexistent/dustpan")).bytes == 0)
    }
}

@Suite("Resolving locations")
struct ResolverTests {
    @Test("Children skip hidden entries and exclusions")
    func children() {
        let sandbox = Sandbox()
        for name in ["com.example.one", "Two", ".hidden", "com.apple.system"] {
            sandbox.folder("Library/Caches/\(name)")
        }
        let resolver = PathResolver(home: sandbox.root)
        let found = resolver.resolve(.children("~/Library/Caches", excluding: ["com.apple.*"]))
        #expect(found.map(\.url.lastPathComponent).sorted() == ["Two", "com.example.one"])
        #expect(found.allSatisfy { $0.isChild })
    }

    @Test("Wildcards match per component and skip what doesn't exist")
    func wildcards() {
        let sandbox = Sandbox()
        sandbox.folder("Library/Application Support/Slack/Cache")
        sandbox.folder("Library/Application Support/Discord")
        sandbox.folder("Library/Application Support/com.apple.foo/Cache")
        let resolver = PathResolver(home: sandbox.root)
        let location = Location.item("~/Library/Application Support/*/Cache", excluding: ["com.apple.*"])
        let found = resolver.resolve(location)
        #expect(found.count == 1)
        #expect(resolver.label(for: found[0].url, location: location) == "Slack/Cache")
    }

    @Test("Name patterns and age filters")
    func matchingAndAge() {
        let sandbox = Sandbox()
        let old = Date().addingTimeInterval(-30 * 86_400)
        sandbox.file("Downloads/Old.dmg", modified: old)
        sandbox.file("Downloads/New.dmg")
        sandbox.file("Downloads/Old.pdf", modified: old)
        let resolver = PathResolver(home: sandbox.root)
        let found = resolver.resolve(.children("~/Downloads", matching: ["*.dmg"], olderThanDays: 7))
        #expect(found.map(\.url.lastPathComponent) == ["Old.dmg"])
    }

    @Test("Presence checks don't need to see inside")
    func presence() {
        let sandbox = Sandbox()
        sandbox.folder("Library/Containers/com.example")
        let resolver = PathResolver(home: sandbox.root)
        #expect(resolver.isPresent("~/Library/Containers/com.example"))
        #expect(!resolver.isPresent("~/Library/Containers/com.missing/Data"))
    }
}

@Suite("Scanning")
struct ScannerTests {
    @Test("A catch-all steps around folders other rules own")
    func split() {
        let sandbox = Sandbox()
        let caches = sandbox.folder("Caches")
        sandbox.folder("Caches/Google/Chrome")
        sandbox.folder("Caches/Google/AndroidStudio")
        sandbox.folder("Caches/pip")
        let claimed = [caches.path + "/pip", caches.path + "/Google/AndroidStudio"]
        #expect(Scanner.split(caches.path + "/pip", around: claimed).isEmpty)
        #expect(Scanner.split(caches.path + "/Google", around: claimed) == [caches.path + "/Google/Chrome"])
    }

    @Test("Finds, measures and never counts a folder twice")
    func endToEnd() async {
        let sandbox = Sandbox()
        sandbox.file("Library/Caches/pip/wheel", bytes: 2_000_000)
        sandbox.file("Library/Caches/com.example/data", bytes: 3_000_000)
        sandbox.file("Library/Caches/tiny/data", bytes: 10)
        let rules = [
            Rule("pip", "pip", .packages, .safe, summary: "x.", aftermath: "x.", locations: [.item("~/Library/Caches/pip")]),
            Rule("rest", "rest", .caches, .safe, summary: "x.", aftermath: "x.",
                 locations: [.children("~/Library/Caches")], isCatchAll: true),
        ]
        let options = ScanOptions(home: sandbox.root, projectRoots: [], minimumBytes: 1_000_000)
        let report = await Scanner(options: options, rules: rules).scan()

        let pip = report.findings.first { $0.id == "pip" }
        let rest = report.findings.first { $0.id == "rest" }
        #expect(pip?.targets.map(\.label) == ["~/Library/Caches/pip"])
        #expect(rest?.targets.map(\.label) == ["com.example"]) // pip is claimed, tiny is under the minimum
        #expect((pip?.bytes ?? 0) >= 2_000_000)
    }
}

@Suite("Projects")
struct ProjectScannerTests {
    let kinds: [(ruleID: String, kind: ArtifactKind)] = [
        ("node", ArtifactKind(folders: ["node_modules"], markers: ["package.json"])),
        ("flutter", ArtifactKind(folders: ["build", ".dart_tool"], markers: ["pubspec.yaml"])),
        ("venv", ArtifactKind(folders: [], innerMarker: "pyvenv.cfg")),
    ]

    @Test("Only folders proven by a marker file count")
    func markers() {
        let sandbox = Sandbox()
        sandbox.file("code/web/package.json")
        sandbox.file("code/web/node_modules/left-pad/index.js")
        sandbox.file("code/web/node_modules/left-pad/node_modules/x/index.js")
        sandbox.file("code/web/build/icon.png") // electron's build/ holds source files
        sandbox.file("code/app/pubspec.yaml")
        sandbox.folder("code/app/build")
        sandbox.folder("code/app/.dart_tool")
        sandbox.folder("code/random/build")
        sandbox.file("code/py/.venv/pyvenv.cfg")
        sandbox.file("code/.hidden/package.json")
        sandbox.folder("code/.hidden/node_modules")

        let hits = ProjectScanner(roots: [sandbox.url("code")], kinds: kinds).find()
        let found = Set(hits.map { "\($0.ruleID):" + $0.url.path.dropFirst(sandbox.url("code").path.count + 1) })
        #expect(found == ["node:web/node_modules", "flutter:app/build", "flutter:app/.dart_tool", "venv:py/.venv"])
    }

    @Test("Names the project after its outermost folder")
    func projectName() {
        let sandbox = Sandbox()
        sandbox.folder("code/mono/.git")
        sandbox.file("code/mono/packages/a/package.json")
        sandbox.folder("code/mono/packages/a/node_modules")
        let hits = ProjectScanner(roots: [sandbox.url("code")], kinds: kinds).find()
        #expect(hits.count == 1)
        #expect(hits.first?.project.lastPathComponent == "mono")
    }
}
