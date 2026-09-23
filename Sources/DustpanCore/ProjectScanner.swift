import Darwin
import Foundation

/// Finds build output inside project folders: `node_modules`, Flutter's `build/`, Cargo's `target/`…
/// A folder only counts when the file that proves what it is sits next to it, so a hand-made
/// `build` folder in a random place is never touched.
public struct ProjectScanner: Sendable {
    public struct Hit: Sendable, Hashable {
        public let ruleID: String
        public let url: URL
        public let modified: Date
        /// The project the folder belongs to, e.g. `~/Code/my-app`.
        public let project: URL
    }

    public let roots: [URL]
    public let kinds: [(ruleID: String, kind: ArtifactKind)]
    public var maxDepth = 8

    public init(roots: [URL], kinds: [(ruleID: String, kind: ArtifactKind)]) {
        self.roots = roots
        self.kinds = kinds
    }

    /// Folders people usually keep code in. Only the ones that exist are returned.
    public static func defaultRoots(home: URL) -> [URL] {
        let names = [
            "Desktop", "Documents", "Developer", "Projects", "Code", "src", "dev", "repos",
            "workspace", "GitHub", "git", "Sites", "work",
        ]
        var seen = Set<String>()
        return names.compactMap { name in
            let url = home.appendingPathComponent(name)
            // The default macOS file system ignores case, so ~/Code and ~/code are one folder.
            guard FileSystem.exists(url.path), seen.insert(name.lowercased()).inserted else { return nil }
            return url
        }
    }

    /// Never worth walking into.
    static let skippedFolders: Set<String> = [".git", ".hg", ".svn", ".Trash", "Library", ".idea", ".vscode"]
    static let skippedExtensions: Set<String> = [
        "app", "xcarchive", "photoslibrary", "imovielibrary", "fcpbundle", "musiclibrary", "tvlibrary",
        "logicx", "band", "framework", "xcframework", "xcodeproj", "xcworkspace", "bundle", "sparsebundle",
    ]
    /// Files that mark the top of a project, used to name it.
    static let projectMarkers = [
        ".git", "package.json", "pubspec.yaml", "Cargo.toml", "pom.xml", "Package.swift", "Podfile",
        "settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts",
        "pyproject.toml", "requirements.txt", "setup.py", "go.mod",
    ]

    public func find(isCancelled: () -> Bool = { false }) -> [Hit] {
        var hits: [Hit] = []
        var seen = Set<String>()
        for root in roots {
            walk(root, into: &hits, seen: &seen, isCancelled: isCancelled)
            if isCancelled() { break }
        }
        return hits
    }

    private func walk(_ root: URL, into hits: inout [Hit], seen: inout Set<String>, isCancelled: () -> Bool) {
        guard let rootPath = strdup(root.path) else { return }
        defer { free(rootPath) }
        var paths: [UnsafeMutablePointer<CChar>?] = [rootPath, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
        defer { fts_close(fts) }

        var visited = 0
        while let entry = fts_read(fts) {
            visited += 1
            if visited % 2048 == 0 && isCancelled() { return }
            guard Int32(entry.pointee.fts_info) == FTS_D else { continue }

            let level = Int(entry.pointee.fts_level)
            let path = String(cString: entry.pointee.fts_path)
            let name = (path as NSString).lastPathComponent
            if level == 0 { continue }

            if level > maxDepth || shouldSkip(name) {
                fts_set(fts, entry, FTS_SKIP)
                continue
            }
            if let ruleID = match(name: name, path: path) {
                // Nested roots (e.g. ~/Desktop and ~/Desktop/Code) would otherwise report twice.
                if seen.insert(path).inserted {
                    let modified: Date
                    if case .found(let info) = FileSystem.lookup(path) { modified = info.modified } else { modified = .distantPast }
                    hits.append(Hit(ruleID: ruleID, url: URL(fileURLWithPath: path), modified: modified, project: projectFolder(of: path, within: root.path)))
                }
                fts_set(fts, entry, FTS_SKIP)
                continue
            }
            // Leftover dependency folders without a package.json are still not worth walking.
            if name == "node_modules" || name.hasPrefix(".") {
                fts_set(fts, entry, FTS_SKIP)
            }
        }
    }

    private func shouldSkip(_ name: String) -> Bool {
        if Self.skippedFolders.contains(name) { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && Self.skippedExtensions.contains(ext)
    }

    private func match(name: String, path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        for (ruleID, kind) in kinds {
            if let inner = kind.innerMarker {
                if FileSystem.exists(path + "/" + inner) { return ruleID }
            } else if kind.folders.contains(name),
                      kind.markers.contains(where: { FileSystem.exists(parent + "/" + $0) }) {
                return ruleID
            }
        }
        return nil
    }

    /// The outermost folder above `path` (but inside the scan root) that looks like a project.
    private func projectFolder(of path: String, within root: String) -> URL {
        var candidate = (path as NSString).deletingLastPathComponent
        var best = candidate
        while candidate.hasPrefix(root + "/") {
            if Self.projectMarkers.contains(where: { FileSystem.exists(candidate + "/" + $0) }) {
                best = candidate
            }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return URL(fileURLWithPath: best)
    }
}
