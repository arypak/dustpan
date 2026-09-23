import Foundation

/// The last line of defence: every path is checked here right before it goes to the Trash,
/// no matter which rule produced it.
public struct SafetyGuard: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        // Resolve the same way `resolvedPath` does, so both sides compare cleanly.
        self.home = home.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Folders Dustpan never touches as a whole.
    static let protectedFolders = [
        "", "Applications", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public",
        "Library", "Library/Application Support", "Library/Caches", "Library/Containers",
        "Library/Group Containers", "Library/Preferences", "Library/Developer", "Library/Developer/Xcode",
        "Library/Logs", "Library/Android", "Library/Android/sdk", "Library/Arduino15",
        ".cache", ".config", ".local", ".local/share", ".android", ".gradle", ".cargo", ".npm", ".bun",
    ]

    /// Folders Dustpan never touches anything inside of.
    static let protectedTrees = [
        ".ssh", ".gnupg", ".Trash", "Library/Keychains", "Library/Mobile Documents", "Library/CloudStorage",
        "Library/Mail", "Library/Messages", "Library/Safari", "Library/Accounts",
        "Pictures/Photos Library.photoslibrary",
    ]

    /// Folders outside the home folder where apps may live.
    static let applicationFolders = ["/Applications"]

    /// Why `url` must not be moved to the Trash, or `nil` when it's fine.
    public func refusal(for url: URL) -> String? {
        let path = resolvedPath(url)
        let homePath = home.path

        if path == "/" || path.isEmpty { return "That's the whole disk." }

        if path.hasPrefix(homePath + "/") {
            let relative = String(path.dropFirst(homePath.count + 1))
            if Self.protectedFolders.contains(relative) {
                return "\(relative) is a folder macOS or you rely on."
            }
            for tree in Self.protectedTrees where relative == tree || relative.hasPrefix(tree + "/") {
                return "Anything inside ~/\(tree) is off limits."
            }
        } else if path == homePath || homePath.hasPrefix(path + "/") {
            return "That's your home folder."
        } else if !isApplicationBundle(path) {
            return "Dustpan only cleans inside your home folder and apps in /Applications."
        }

        if FileSystem.exists(path + "/.git") {
            return "It contains a Git repository, so it looks like source code."
        }
        return nil
    }

    private func isApplicationBundle(_ path: String) -> Bool {
        guard path.hasSuffix(".app") else { return false }
        let folders = Self.applicationFolders + [home.path + "/Applications"]
        return folders.contains { folder in
            guard path.hasPrefix(folder + "/") else { return false }
            let depth = path.dropFirst(folder.count + 1).split(separator: "/").count
            return depth == 1 || depth == 2 // Apps can sit one folder deep, e.g. /Applications/Adobe X/X.app
        }
    }

    /// The real location, with `..` and symlinked parent folders resolved.
    /// The last component is kept as is: trashing a symlink moves only the link.
    private func resolvedPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.appendingPathComponent(standardized.lastPathComponent).path
    }
}
