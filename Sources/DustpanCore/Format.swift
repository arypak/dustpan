import Foundation

/// Formatting that follows Dustpan's language setting rather than the process locale,
/// so the CLI, the app and the README read the same.
public enum Format {
    /// Decimal units, like Finder and System Settings: 1 GB = 1,000,000,000 bytes.
    public static func bytes(_ count: Int64, language: Language = Localization.language) -> String {
        let units = ["KB", "MB", "GB", "TB", "PB"]
        guard count >= 1000 else { return Localization.format("%@ bytes", [String(count)], in: language) }
        var value = Double(count)
        var unit = -1
        // 999.6 MB would print as "1000 MB", so step up a unit before rounding gets there.
        while value >= 999.5 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        var rounded = value >= 99.95 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        if language == .turkish { rounded = rounded.replacingOccurrences(of: ".", with: ",") }
        return "\(rounded) \(units[unit])"
    }

    public static func relative(_ date: Date, now: Date = Date(), language: Language = Localization.language) -> String {
        func say(_ key: String, _ number: Int? = nil) -> String {
            Localization.format(key, number.map { [String($0)] } ?? [], in: language)
        }
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<0: return say("just now")
        case 0: return say("today")
        case 1: return say("yesterday")
        case 2..<14: return say("%@ days ago", days)
        case 14..<60: return say("%@ weeks ago", days / 7)
        case 60..<365: return say("%@ months ago", days / 30)
        default:
            let years = days / 365
            return years == 1 ? say("a year ago") : say("%@ years ago", years)
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
