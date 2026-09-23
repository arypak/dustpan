import AppKit
import DustpanCore
import SwiftUI

@main
struct DustpanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Dustpan", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Sweep") {
                Button("Scan Again") { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.phase == .scanning || model.phase == .cleaning)
                Button("Select Everything Safe") { model.select(.safe) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(model.report == nil)
                Button("Clear Selection") { model.selection.removeAll() }
                    .disabled(model.selection.isEmpty)
                Divider()
                Button("Move to Trash…") { model.sheet = .confirm }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.selection.isEmpty || model.phase != .ready)
                Divider()
                Button("Open Trash") { SystemActions.openTrash() }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also behave like a normal app when started straight from `swift run`.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
