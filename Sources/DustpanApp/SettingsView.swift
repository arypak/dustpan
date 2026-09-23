import AppKit
import DustpanCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: URL?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                List(selection: $selection) {
                    ForEach(model.projectRoots, id: \.self) { root in
                        Label(Format.path(root), systemImage: "folder")
                            .tag(root)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 150)
                HStack {
                    Button("Add Folder…", action: addFolder)
                    Button("Remove") {
                        model.projectRoots.removeAll { $0 == selection }
                        selection = nil
                    }
                    .disabled(selection == nil)
                    Spacer()
                    Button("Restore Defaults") {
                        model.projectRoots = ProjectScanner.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser)
                    }
                }
            } header: {
                Text("Project folders")
            } footer: {
                Text("Dustpan looks inside these for build output such as node_modules, Flutter build folders and Cargo targets. Changes apply on the next scan.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 380)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !model.projectRoots.contains(url) {
            model.projectRoots.append(url)
        }
    }
}
