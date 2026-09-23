import CoreServices
import Darwin
import Foundation

/// Finders for the rules that need more than a list of paths.
enum Discoverers {
    // MARK: Apps

    static func applicationBundles(home: URL) -> [URL] {
        var bundles: [URL] = []
        for folder in ["/Applications", home.path + "/Applications"] {
            for name in FileSystem.list(folder) ?? [] where !name.hasPrefix(".") {
                let path = folder + "/" + name
                guard case .found(let entry) = FileSystem.lookup(path), entry.isDirectory, !entry.isSymlink else { continue }
                if name.hasSuffix(".app") {
                    bundles.append(URL(fileURLWithPath: path))
                } else if name != "Utilities" {
                    // Some vendors install into a folder, e.g. /Applications/Adobe Photoshop 2025/.
                    for inner in FileSystem.list(path) ?? [] where inner.hasSuffix(".app") {
                        bundles.append(URL(fileURLWithPath: path + "/" + inner))
                    }
                }
            }
        }
        return bundles
    }

    /// When the app was last opened, according to Spotlight.
    static func lastOpened(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    // MARK: Simulators

    struct Runtime {
        let identifier: String
        let name: String
        let bytes: Int64
        let path: String
        let lastUsed: Date?
    }

    struct Device {
        let name: String
        let runtime: String
        let folder: URL
    }

    /// Only ask `xcrun` when Xcode is really there; without developer tools it pops up an installer.
    static var hasDeveloperTools: Bool {
        guard let data = run("/usr/bin/xcode-select", ["-p"]),
              let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return FileSystem.exists(path + "/usr/bin/simctl") || FileSystem.exists(path + "/Platforms")
    }

    static func simulatorRuntimes() -> [Runtime] {
        guard hasDeveloperTools,
              let data = run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            return []
        }
        let dates = ISO8601DateFormatter()
        return json.values.compactMap { runtime in
            guard runtime["deletable"] as? Bool == true,
                  let identifier = runtime["identifier"] as? String,
                  let bytes = (runtime["sizeBytes"] as? NSNumber)?.int64Value else { return nil }
            let platform = platformName(runtime["platformIdentifier"] as? String ?? "")
            let version = runtime["version"] as? String ?? "?"
            let build = runtime["build"] as? String
            return Runtime(
                identifier: identifier,
                name: "\(platform) \(version)" + (build.map { " (\($0))" } ?? ""),
                bytes: bytes,
                path: runtime["path"] as? String ?? "/Library/Developer/CoreSimulator",
                lastUsed: (runtime["lastUsedAt"] as? String).flatMap(dates.date(from:))
            )
        }
        .sorted { $0.name < $1.name }
    }

    static func unavailableSimulators(home: URL) -> [Device] {
        guard FileSystem.exists(home.path + "/Library/Developer/CoreSimulator/Devices"), hasDeveloperTools,
              let data = run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = json["devices"] as? [String: [[String: Any]]] else {
            return []
        }
        return byRuntime.flatMap { runtime, devices in
            devices.compactMap { device -> Device? in
                guard let udid = device["udid"] as? String else { return nil }
                let folder = (device["dataPath"] as? String).map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
                    ?? home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(udid)")
                return Device(name: device["name"] as? String ?? udid, runtime: runtimeName(runtime), folder: folder)
            }
        }
        .sorted { $0.name < $1.name }
    }

    static func platformName(_ identifier: String) -> String {
        switch identifier {
        case let id where id.contains("iphone"): "iOS"
        case let id where id.contains("watch"): "watchOS"
        case let id where id.contains("appletv"): "tvOS"
        case let id where id.contains("xr"): "visionOS"
        default: "Simulator"
        }
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-5` → `iOS 26.5`
    static func runtimeName(_ key: String) -> String {
        guard let last = key.split(separator: ".").last else { return key }
        let parts = last.split(separator: "-")
        guard let platform = parts.first else { return key }
        return ([String(platform)] + [parts.dropFirst().joined(separator: ".")]).joined(separator: " ")
    }

    // MARK: Device backups

    /// Device name and backup date from a backup's Info.plist.
    static func backupInfo(_ folder: URL) -> (name: String, date: Date?)? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let name = plist["Device Name"] as? String ?? plist["Display Name"] as? String ?? folder.lastPathComponent
        return (name, plist["Last Backup Date"] as? Date)
    }

    // MARK: Processes

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return process.terminationStatus == 0 ? data : nil
    }
}

public enum SystemInfo {
    public static func disk(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> DiskInfo? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? home.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity else {
            return nil
        }
        let name = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
        let available = Int64(values.volumeAvailableCapacity ?? 0)
        return DiskInfo(
            volumeName: name ?? "Macintosh HD",
            total: Int64(total),
            available: available,
            availableIncludingPurgeable: values.volumeAvailableCapacityForImportantUsage ?? available
        )
    }

    /// macOS gives no API for this, so try to open files only Full Disk Access unlocks.
    public static func hasFullDiskAccess(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            home.path + "/Library/Safari",
            home.path + "/Library/Containers/com.apple.stocks",
        ]
        for probe in probes {
            let descriptor = open(probe, O_RDONLY)
            if descriptor >= 0 {
                close(descriptor)
                return true
            }
        }
        return false
    }

    /// The Trash's size, or `nil` when Dustpan isn't allowed to look inside.
    public static func trashSize(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Int64? {
        let trash = home.appendingPathComponent(".Trash")
        guard FileSystem.list(trash.path) != nil else { return nil }
        return DirectorySizer.measure(trash).bytes
    }
}
