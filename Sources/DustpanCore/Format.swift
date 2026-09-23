import Foundation

/// Locale-independent formatting, so the CLI, the app and the README all read the same.
public enum Format {
    /// Decimal units, like Finder and System Settings: 1 GB = 1,000,000,000 bytes.
    public static func bytes(_ count: Int64) -> String {
        let units = ["KB", "MB", "GB", "TB", "PB"]
        guard count >= 1000 else { return "\(count) bytes" }
        var value = Double(count)
        var unit = -1
        // 999.6 MB would print as "1000 MB", so step up a unit before rounding gets there.
        while value >= 999.5 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let rounded = value >= 99.95 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(rounded) \(units[unit])"
    }

    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<0: return "just now"
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        case 60..<365: return "\(days / 30) months ago"
        default:
            let years = days / 365
            return years == 1 ? "a year ago" : "\(years) years ago"
        }
    }

    /// `/Users/you/Library/Caches` → `~/Library/Caches`
    public static func path(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let path = url.path
        let homePath = home.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
