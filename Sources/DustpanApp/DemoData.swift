import DustpanCore
import Foundation

/// A made-up but typical developer Mac, for screenshots that don't reveal anyone's real files.
/// Start the app with `DUSTPAN_DEMO=1` to see it.
enum DemoData {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["DUSTPAN_DEMO"] != nil }

    static func report() -> ScanReport {
        let home = URL(fileURLWithPath: "/Users/you")
        let now = Date()
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        func item(_ path: String, _ gb: Double, label: String? = nil, detail: String? = nil, modified: Date? = nil, command: String? = nil) -> Target {
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : home.appendingPathComponent(path)
            return Target(url: url, bytes: Int64(gb * 1_000_000_000), modified: modified,
                          label: label ?? "~/" + path, detail: detail, command: command)
        }
        func child(_ path: String, _ gb: Double, days: Double) -> Target {
            item(path, gb, label: (path as NSString).lastPathComponent, detail: "Modified \(Format.relative(ago(days)))", modified: ago(days))
        }
        func project(_ path: String, _ gb: Double, days: Double) -> Target {
            let parts = path.split(separator: "/")
            return item("Code/" + path, gb, label: parts.joined(separator: "/"), detail: "~/Code · touched \(Format.relative(ago(days)))", modified: ago(days))
        }
        func app(_ name: String, _ gb: Double, days: Double) -> Target {
            item("/Applications/\(name).app", gb, label: name, detail: "Last opened \(Format.relative(ago(days)))", modified: ago(days))
        }

        let found: [String: [Target]] = [
            "app-update-leftovers": [child("Library/Caches/com.microsoft.VSCode.ShipIt", 0.61, days: 20)],
            "browser-caches": [
                item("Library/Application Support/Slack/Cache", 0.54, label: "Slack/Cache"),
                item("Library/Application Support/discord/Cache", 0.38, label: "discord/Cache"),
                item("Library/Application Support/Code/Cache", 0.21, label: "Code/Cache"),
            ],
            "logs": [child("Library/Logs/DiagnosticReports", 0.12, days: 3)],
            "app-caches": [
                child("Library/Caches/Google/Chrome", 1.24, days: 1), child("Library/Caches/com.spotify.client", 0.86, days: 2),
                child("Library/Caches/com.tinyspeck.slackmacgap", 0.42, days: 1),
            ],
            "xcode-derived-data": [item("Library/Developer/Xcode/DerivedData", 18.4)],
            "xcode-device-support": [
                child("Library/Developer/Xcode/iOS DeviceSupport/iPhone16,1 18.5 (22F76)", 4.1, days: 12),
                child("Library/Developer/Xcode/iOS DeviceSupport/iPhone16,1 18.3 (22D63)", 3.9, days: 96),
                child("Library/Developer/Xcode/iOS DeviceSupport/iPhone14,2 17.6 (21G80)", 3.2, days: 280),
            ],
            "xcode-archives": [child("Library/Developer/Xcode/Archives/2025-06-02", 1.1, days: 110), child("Library/Developer/Xcode/Archives/2025-03-18", 0.9, days: 186)],
            "simulator-runtimes": [
                item("/Library/Developer/CoreSimulator/Volumes/iOS_22F77", 8.4, label: "iOS 18.5 (22F77)", detail: "Last used yesterday", command: "xcrun simctl runtime delete 2E4B…"),
                item("/Library/Developer/CoreSimulator/Volumes/iOS_21F79", 7.9, label: "iOS 17.5 (21F79)", detail: "Last used 7 months ago", command: "xcrun simctl runtime delete 9A1C…"),
            ],
            "simulator-unavailable": [item("Library/Developer/CoreSimulator/Devices/5C2A", 1.3, label: "iPhone 15 Pro · iOS 17.2")],
            "homebrew-cache": [item("Library/Caches/Homebrew", 2.1)],
            "npm-cache": [item(".npm/_cacache", 3.2)],
            "yarn-cache": [item("Library/Caches/Yarn", 2.4)],
            "pip-cache": [item("Library/Caches/pip", 1.4)],
            "uv-cache": [item(".cache/uv", 6.8)],
            "gradle-cache": [item(".gradle/caches", 5.6)],
            "cocoapods-cache": [item("Library/Caches/CocoaPods", 1.8)],
            "test-browsers": [item("Library/Caches/ms-playwright", 1.1)],
            "node-modules": [
                project("weather-app/node_modules", 0.78, days: 9), project("portfolio/node_modules", 0.54, days: 40),
                project("api-server/node_modules", 0.41, days: 130),
            ],
            "js-build-caches": [project("portfolio/.next", 0.62, days: 40)],
            "flutter-build": [project("habit-tracker/build", 2.3, days: 22), project("habit-tracker/.dart_tool", 0.9, days: 22)],
            "target-folders": [project("cli-tool/target", 3.4, days: 61)],
            "python-venvs": [project("ml-notebook/.venv", 2.8, days: 75)],
            "android-system-images": [child("Library/Android/sdk/system-images/android-34", 3.2, days: 200)],
            "docker-desktop": [item("Library/Containers/com.docker.docker/Data/vms/0/data", 24.6)],
            "ollama-models": [item(".ollama/models", 9.1)],
            "huggingface-cache": [child(".cache/huggingface/hub/models--openai--whisper-large-v3", 3.1, days: 50)],
            "large-apps": [
                app("Xcode", 12.4, days: 0), app("Final Cut Pro", 6.1, days: 240), app("Android Studio", 3.4, days: 150),
                app("Microsoft Word", 2.9, days: 33),
            ],
            "old-installers": [child("Downloads/Docker.dmg", 0.58, days: 45), child("Downloads/Figma.dmg", 0.12, days: 80)],
        ]
        let locked: Set<String> = ["sandboxed-app-caches", "device-backups"]

        let order = Dictionary(uniqueKeysWithValues: DustpanCore.Category.allCases.enumerated().map { ($1, $0) })
        let findings = Catalog.rules.compactMap { rule -> Finding? in
            if locked.contains(rule.id) { return Finding(rule: rule, targets: [], locked: true) }
            guard let targets = found[rule.id] else { return nil }
            return Finding(rule: rule, targets: targets.sorted { $0.bytes > $1.bytes })
        }
        .sorted { a, b in
            a.rule.category != b.rule.category ? order[a.rule.category]! < order[b.rule.category]! : a.bytes > b.bytes
        }
        return ScanReport(
            findings: findings,
            disk: DiskInfo(volumeName: "Macintosh HD", total: 494_380_000_000, available: 61_200_000_000, availableIncludingPurgeable: 70_900_000_000),
            hasFullDiskAccess: false,
            trashBytes: nil,
            startedAt: now,
            duration: 4.2
        )
    }
}
