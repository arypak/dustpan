import AppKit
import DustpanCore

/// Small bridges to Finder and System Settings.
@MainActor
enum SystemActions {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openTrash() {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        NSWorkspace.shared.open(trash)
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Moves items to the Trash through Finder, which can ask for an administrator password.
enum FinderTrash {
    static func move(_ targets: [Target]) -> CleanResult {
        var result = CleanResult()
        let safety = SafetyGuard()
        for target in targets {
            if let reason = safety.refusal(for: target.url) {
                result.failures.append(.init(target: target, reason: reason, needsAdmin: false))
                continue
            }
            let path = target.url.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e", "set target to POSIX file \"\(path)\" as alias",
                "-e", "tell application \"Finder\" to delete target",
            ]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                result.failures.append(.init(target: target, reason: error.localizedDescription, needsAdmin: false))
                continue
            }
            if process.terminationStatus == 0 && !FileManager.default.fileExists(atPath: target.url.path) {
                result.moved.append(target)
            } else {
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                result.failures.append(.init(
                    target: target,
                    reason: message.isEmpty ? L("Finder couldn't move it.") : message.trimmingCharacters(in: .whitespacesAndNewlines),
                    needsAdmin: false
                ))
            }
        }
        return result
    }
}
