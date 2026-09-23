import Foundation
import Testing
@testable import DustpanCore

@Suite("Safety guard")
struct SafetyGuardTests {
    let home = URL(fileURLWithPath: "/Users/tester")
    var safety: SafetyGuard { SafetyGuard(home: home) }

    func refused(_ path: String) -> Bool {
        safety.refusal(for: URL(fileURLWithPath: path.replacingOccurrences(of: "~", with: home.path))) != nil
    }

    @Test("Refuses the disk, system folders and the home folder itself", arguments: [
        "/", "/System", "/System/Library/Caches", "/usr/local/bin", "/Library/Caches", "/Users",
        "/Users/tester", "/Applications", "/Applications/Foo.app/Contents", "/private/var/folders",
    ])
    func systemPaths(_ path: String) {
        #expect(refused(path))
    }

    @Test("Refuses folders people and macOS rely on", arguments: [
        "~/Library", "~/Documents", "~/Desktop", "~/Downloads", "~/Pictures", "~/Library/Caches",
        "~/Library/Application Support", "~/Library/Containers", "~/Library/Preferences", "~/.cache", "~/.config",
    ])
    func protectedFolders(_ path: String) {
        #expect(refused(path))
    }

    @Test("Refuses anything inside private trees", arguments: [
        "~/.ssh/id_ed25519", "~/Library/Keychains/login.keychain-db", "~/Library/Mobile Documents/com~apple~CloudDocs/x",
        "~/Library/CloudStorage/Dropbox/y", "~/.Trash/old", "~/Library/Messages/Attachments", "~/Library/Mail/V10",
        "~/Pictures/Photos Library.photoslibrary/originals",
    ])
    func protectedTrees(_ path: String) {
        #expect(refused(path))
    }

    @Test("Allows what the rules are meant to clean", arguments: [
        "~/.cache/uv", "~/Library/Caches/com.example.app", "~/Library/Developer/Xcode/DerivedData",
        "~/Desktop/project/node_modules", "~/Library/Application Support/Claude/vm_bundles",
        "/Applications/Big Game.app", "/Applications/Adobe Photoshop/Adobe Photoshop.app", "~/Applications/Tool.app",
    ])
    func allowed(_ path: String) {
        #expect(!refused(path))
    }

    @Test("Sees through .. tricks")
    func dotDot() {
        #expect(refused("~/Library/Caches/../../Documents"))
        #expect(refused("~/.cache/uv/../../.ssh"))
    }

    @Test("Refuses folders that hold a Git repository")
    func gitRepository() {
        let sandbox = Sandbox()
        let repo = sandbox.folder("home/Code/app/build")
        sandbox.folder("home/Code/app/build/.git")
        let safety = SafetyGuard(home: sandbox.url("home"))
        #expect(safety.refusal(for: repo) != nil)
        #expect(safety.refusal(for: sandbox.folder("home/Code/app/node_modules")) == nil)
    }
}
