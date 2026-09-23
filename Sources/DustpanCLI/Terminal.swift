import Darwin
import DustpanCore
import Foundation

/// ANSI styling that switches itself off for pipes, files and `NO_COLOR`.
enum Style {
    nonisolated(unsafe) static var enabled = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func wrap(_ text: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    static func bold(_ text: String) -> String { wrap(text, "1") }
    static func dim(_ text: String) -> String { wrap(text, "2") }
    static func green(_ text: String) -> String { wrap(text, "32") }
    static func yellow(_ text: String) -> String { wrap(text, "33") }
    static func magenta(_ text: String) -> String { wrap(text, "35") }
    static func cyan(_ text: String) -> String { wrap(text, "36") }
    static func red(_ text: String) -> String { wrap(text, "31") }

    static func safety(_ safety: Safety, _ text: String) -> String {
        switch safety {
        case .safe: green(text)
        case .caution: yellow(text)
        case .review: magenta(text)
        }
    }
}

/// Padding that ignores ANSI codes and counts characters the way a terminal draws them.
extension String {
    var visibleWidth: Int {
        var width = 0
        var inEscape = false
        for scalar in unicodeScalars {
            if scalar == "\u{1B}" { inEscape = true; continue }
            if inEscape { if scalar == "m" { inEscape = false }; continue }
            width += 1
        }
        return width
    }

    func padded(to width: Int) -> String {
        self + String(repeating: " ", count: max(0, width - visibleWidth))
    }

    func leftPadded(to width: Int) -> String {
        String(repeating: " ", count: max(0, width - visibleWidth)) + self
    }

    func truncated(to width: Int) -> String {
        count > width ? String(prefix(max(0, width - 1))) + "…" : self
    }
}

/// A one-line progress indicator on stderr, so stdout stays clean for pipes.
final class ProgressLine: @unchecked Sendable {
    private let enabled = isatty(STDERR_FILENO) == 1
    private let lock = NSLock()
    private var lastDraw = Date.distantPast
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var frame = 0

    func update(_ progress: ScanProgress) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(lastDraw) > 0.08 || progress.completed == progress.total else { return }
        lastDraw = now
        frame = (frame + 1) % frames.count
        let count = progress.total > 0 ? " \(progress.completed)/\(progress.total)" : ""
        let line = " \(frames[frame]) Scanning\(count)  \(progress.current)".truncated(to: 72)
        FileHandle.standardError.write(Data("\r\u{1B}[2K\(Style.dim(line))".utf8))
    }

    func clear() {
        guard enabled else { return }
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
    }
}

func printError(_ message: String) {
    fflush(stdout) // keep the order right when both streams go to the same place
    FileHandle.standardError.write(Data((Style.red("error: ") + message + "\n").utf8))
}

func diskBar(_ fraction: Double, width: Int = 32) -> String {
    let filled = Int((fraction * Double(width)).rounded())
    let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, width - filled))
    let colored = fraction > 0.9 ? Style.red(bar) : fraction > 0.75 ? Style.yellow(bar) : Style.cyan(bar)
    return colored
}
