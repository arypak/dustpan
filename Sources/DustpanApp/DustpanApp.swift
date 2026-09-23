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
                .id(model.language)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(model.L("Sweep")) {
                Button(model.L("Scan Again")) { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.phase == .scanning || model.phase == .cleaning)
                Button(model.L("Select All Safe")) { model.select(.safe) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(model.report == nil)
                Button(model.L("Clear Selection")) { model.selection.removeAll() }
                    .disabled(model.selection.isEmpty)
                Divider()
                Button(model.L("Move to Trash…")) { model.sheet = .confirm }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.selection.isEmpty || model.phase != .ready)
                Divider()
                Button(model.L("Open Trash")) { SystemActions.openTrash() }
            }
            CommandGroup(after: .sidebar) {
                Picker(model.L("Appearance"), selection: $model.appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .id(model.language)
        }
    }
}

extension AppModel {
    /// Translates like `L(_:)`, and also tells SwiftUI to redraw the caller when the language changes.
    func L(_ key: String) -> String {
        _ = language
        return DustpanCore.L(key)
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
