import Foundation
import Testing
@testable import DustpanCore

@Suite("Classification")
struct ClassificationTests {
    /// Scans a sandbox home with the real catalog, limited to `ids`.
    private func scan(_ sandbox: Sandbox, _ ids: Set<String>) async -> [String: [String]] {
        let options = ScanOptions(home: sandbox.root, projectRoots: [], ruleIDs: ids)
        let report = await Scanner(options: options).scan()
        return Dictionary(uniqueKeysWithValues: report.findings.map { finding in
            (finding.id, finding.targets.map { String($0.url.path.dropFirst(sandbox.root.path.count + 1)) }.sorted())
        })
    }

    @Test("Poetry's virtual environments need a review, its downloads don't")
    func poetry() async {
        let sandbox = Sandbox()
        sandbox.file("Library/Caches/pypoetry/cache/repositories/pypi/x", bytes: 2_000_000)
        sandbox.file("Library/Caches/pypoetry/artifacts/ab/wheel.whl", bytes: 2_000_000)
        sandbox.file("Library/Caches/pypoetry/virtualenvs/shop-Xy12-py3.12/lib/site.py", bytes: 2_000_000)
        sandbox.file("Library/Caches/pypoetry/virtualenvs/blog-Zq34-py3.12/lib/site.py", bytes: 2_000_000)

        #expect(Catalog.rule(id: "poetry-venvs")?.safety == .review)
        let found = await scan(sandbox, ["poetry-cache", "poetry-venvs", "app-caches"])
        #expect(found["poetry-cache"] == ["Library/Caches/pypoetry/artifacts", "Library/Caches/pypoetry/cache"])
        #expect(found["poetry-venvs"] == [
            "Library/Caches/pypoetry/virtualenvs/blog-Zq34-py3.12",
            "Library/Caches/pypoetry/virtualenvs/shop-Xy12-py3.12",
        ])
        #expect(found["app-caches"] == nil)
    }

    @Test("A catch-all cleaned on its own leaves what stricter rules own")
    func catchAllAlone() async {
        let sandbox = Sandbox()
        sandbox.file("Library/Caches/pypoetry/virtualenvs/shop-Xy12-py3.12/lib/site.py", bytes: 2_000_000)
        sandbox.file("Library/Caches/ms-playwright/chromium/chrome", bytes: 2_000_000)
        sandbox.file("Library/Caches/pip/wheel", bytes: 2_000_000)
        sandbox.file("Library/Caches/com.example.app/data", bytes: 2_000_000)

        let found = await scan(sandbox, ["app-caches"])
        #expect(found == ["app-caches": ["Library/Caches/com.example.app"]])
    }

    @Test("Yarn's shared cache, which Plug'n'Play projects run from, isn't marked safe")
    func yarn() {
        #expect(Catalog.rule(id: "yarn-berry-cache")?.safety == .caution)
        let safe = Catalog.rules.filter { $0.safety == .safe }.flatMap(\.locations).map(\.pattern)
        #expect(!safe.contains { $0.contains(".yarn/berry") || $0.hasSuffix("/pypoetry") })
    }

    @Test("A build folder that holds sources isn't build output")
    func sourceNamedBuild() {
        let kinds: [(ruleID: String, kind: ArtifactKind)] = Catalog.rules.compactMap { rule in
            if case .projects(let kind) = rule.discovery { (rule.id, kind) } else { nil }
        }
        let sandbox = Sandbox()
        // Real output: files sit in subfolders.
        sandbox.file("code/app/pubspec.yaml")
        sandbox.file("code/app/build/.last_build_id")
        sandbox.file("code/app/build/app/outputs/app.apk")
        sandbox.file("code/app/.dart_tool/package_config.json")
        sandbox.file("code/app/android/build.gradle")
        sandbox.file("code/app/android/build/intermediates/x.bin")
        sandbox.file("code/crate/Cargo.toml")
        sandbox.file("code/crate/target/CACHEDIR.TAG")
        sandbox.file("code/crate/target/debug/crate")
        sandbox.file("code/site/package.json")
        sandbox.file("code/site/.next/package.json") // Next.js writes one into its output
        // A package that happens to be called build, and a folder of build scripts.
        sandbox.file("code/mono/pubspec.yaml")
        sandbox.file("code/mono/build/pubspec.yaml")
        sandbox.file("code/mono/build/lib/build.dart")
        sandbox.file("code/tool/build.gradle")
        sandbox.file("code/tool/build/release.sh")
        sandbox.file("code/tool/build/signing/key.properties")
        sandbox.file("code/svc/pom.xml")
        sandbox.file("code/svc/target/README.md")

        let hits = ProjectScanner(roots: [sandbox.url("code")], kinds: kinds).find()
        let found = Set(hits.map { String($0.url.path.dropFirst(sandbox.url("code").path.count + 1)) })
        #expect(found == ["app/build", "app/.dart_tool", "app/android/build", "crate/target", "site/.next"])
    }
}
