import Darwin
import Foundation

public struct SizeResult: Sendable, Hashable {
    /// Bytes allocated on disk, like `du`: sparse files count what they use, hard links count once.
    public var bytes: Int64
    /// Folders inside that couldn't be read.
    public var unreadable: Int
}

/// Measures disk usage with `fts(3)`, the same walker `du` uses.
public enum DirectorySizer {
    private struct Inode: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    public static func measure(_ url: URL, isCancelled: () -> Bool = { false }) -> SizeResult {
        var result = SizeResult(bytes: 0, unreadable: 0)
        guard let root = strdup(url.path) else { return result }
        defer { free(root) }

        var paths: [UnsafeMutablePointer<CChar>?] = [root, nil]
        // Physical walk: don't follow symlinks. XDEV: stay on this volume.
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return result }
        defer { fts_close(fts) }

        var seenLinks = Set<Inode>()
        var visited = 0
        while let entry = fts_read(fts) {
            visited += 1
            if visited % 4096 == 0 && isCancelled() { break }

            switch Int32(entry.pointee.fts_info) {
            case FTS_D, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let stat = entry.pointee.fts_statp?.pointee else { continue }
                let isDirectory = Int32(entry.pointee.fts_info) == FTS_D
                if !isDirectory && stat.st_nlink > 1 {
                    guard seenLinks.insert(Inode(device: stat.st_dev, inode: stat.st_ino)).inserted else { continue }
                }
                result.bytes += Int64(stat.st_blocks) * 512
            case FTS_DNR, FTS_ERR, FTS_NS:
                result.unreadable += 1
            default:
                break // FTS_DP (leaving a directory), FTS_DC (cycle), FTS_DOT
            }
        }
        return result
    }
}
