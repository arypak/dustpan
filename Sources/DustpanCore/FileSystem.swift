import Darwin
import Foundation

/// Thin, fast wrappers over POSIX calls. `FileManager` hides errno, and errno is how
/// we tell "doesn't exist" apart from "macOS won't let us look".
enum FileSystem {
    struct Entry {
        let isDirectory: Bool
        let isSymlink: Bool
        let modified: Date
    }

    enum Lookup {
        case found(Entry)
        case missing
        case denied
    }

    static func lookup(_ path: String) -> Lookup {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return (errno == EPERM || errno == EACCES) ? .denied : .missing
        }
        let type = info.st_mode & S_IFMT
        return .found(Entry(
            isDirectory: type == S_IFDIR,
            isSymlink: type == S_IFLNK,
            modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        ))
    }

    static func exists(_ path: String) -> Bool {
        if case .found = lookup(path) { return true }
        return false
    }

    /// Names in a directory, without `.` and `..`. `nil` when it can't be read.
    static func list(_ path: String) -> [String]? {
        guard let dir = opendir(path) else { return nil }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(length), as: UTF8.self)
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }

    /// Shell-style name matching, case-insensitive like the default macOS file system.
    static func matches(_ name: String, _ pattern: String) -> Bool {
        fnmatch(pattern, name, FNM_CASEFOLD) == 0
    }

    static func matchesAny(_ name: String, _ patterns: [String]) -> Bool {
        patterns.contains { matches(name, $0) }
    }
}

/// Turns rule locations into concrete paths on this Mac.
struct PathResolver {
    let home: URL

    struct Candidate {
        let url: URL
        let modified: Date
        /// True for children of a directory, false for a location's own path.
        let isChild: Bool
    }

    func expandTilde(_ pattern: String) -> String {
        if pattern == "~" { return home.path }
        if pattern.hasPrefix("~/") { return home.path + pattern.dropFirst(1) }
        return pattern
    }

    /// Expands `*` wildcards component by component. Hidden entries never match a wildcard.
    func expand(_ pattern: String, excluding: [String] = []) -> [String] {
        let expanded = expandTilde(pattern)
        guard expanded.hasPrefix("/") else { return [] }
        var paths = ["/"]
        for component in expanded.split(separator: "/").map(String.init) {
            var next: [String] = []
            for base in paths {
                let prefix = base == "/" ? "/" : base + "/"
                if component.contains("*") || component.contains("?") {
                    for name in FileSystem.list(base) ?? [] where !name.hasPrefix(".") {
                        if FileSystem.matches(name, component) && !FileSystem.matchesAny(name, excluding) {
                            next.append(prefix + name)
                        }
                    }
                } else {
                    next.append(prefix + component)
                }
            }
            paths = next
            if paths.isEmpty { break }
        }
        return paths.filter(FileSystem.exists).sorted()
    }

    func resolve(_ location: Location, now: Date = Date()) -> [Candidate] {
        var result: [Candidate] = []
        for path in expand(location.pattern, excluding: location.excluding) {
            guard case .found(let entry) = FileSystem.lookup(path) else { continue }
            switch location.mode {
            case .item:
                result.append(Candidate(url: URL(fileURLWithPath: path), modified: entry.modified, isChild: false))
            case .children:
                guard entry.isDirectory else { continue }
                for name in (FileSystem.list(path) ?? []).sorted() {
                    if name.hasPrefix(".") { continue }
                    if FileSystem.matchesAny(name, location.excluding) { continue }
                    if !location.matching.isEmpty && !FileSystem.matchesAny(name, location.matching) { continue }
                    let childPath = path + "/" + name
                    guard case .found(let child) = FileSystem.lookup(childPath) else { continue }
                    if let days = location.olderThanDays,
                       now.timeIntervalSince(child.modified) < TimeInterval(days) * 86_400 {
                        continue
                    }
                    result.append(Candidate(url: URL(fileURLWithPath: childPath), modified: child.modified, isChild: true))
                }
            }
        }
        return result
    }
}
