import Foundation

/// An app that's open right now. The app and the CLI fill these in from `NSWorkspace`.
public struct RunningApp: Sendable, Hashable {
    public let name: String
    public let bundleID: String?

    public init(name: String, bundleID: String?) {
        self.name = name
        self.bundleID = bundleID
    }
}

extension Target {
    /// The open app this target belongs to, judged by the folder it sits in: one named after the app's
    /// bundle id (`Caches/com.tinyspeck.slackmacgap`, `Caches/com.x.app.ShipIt`) or after the app itself
    /// (`Application Support/Slack/Cache`, `Caches/Google/Chrome` for "Google Chrome").
    /// Only app data folders count, so a project in `~/Code` never belongs to an app called "Code".
    public func owner(among apps: [RunningApp], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> RunningApp? {
        let appFolders = ["Caches", "Application Support", "Logs", "Containers", "Group Containers"]
        let library = home.appendingPathComponent("Library").pathComponents.map { $0.lowercased() }
        let parts = url.pathComponents.map { $0.lowercased() }
        guard parts.count > library.count + 1,
              Array(parts.prefix(library.count)) == library,
              appFolders.map({ $0.lowercased() }).contains(parts[library.count]) else { return nil }

        let first = parts[library.count + 1]
        let firstTwo = parts.count > library.count + 2 ? first + " " + parts[library.count + 2] : nil
        return apps.first { app in
            if let id = app.bundleID?.lowercased(), first == id || first.hasPrefix(id + ".") { return true }
            let name = app.name.lowercased()
            return first == name || firstTwo == name
        }
    }
}
