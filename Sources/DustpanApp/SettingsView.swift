import AppKit
import DustpanCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            FolderSettings()
                .tabItem { Label(L("Project Folders"), systemImage: "folder") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker(L("Language"), selection: $model.languagePreference) {
                ForEach(LanguagePreference.allCases) { Text($0.title).tag($0) }
            }
            Picker(L("Appearance"), selection: $model.appearance) {
                ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(L("Menus switch language the next time you open Dustpan."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(height: 200)
    }
}

private struct FolderSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: URL?

    var body: some View {
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
                    Button(L("Add Folder…"), action: addFolder)
                    Button(L("Remove")) {
                        model.projectRoots.removeAll { $0 == selection }
                        selection = nil
                    }
                    .disabled(selection == nil)
                    Spacer()
                    Button(L("Restore Defaults")) {
                        model.projectRoots = ProjectScanner.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser)
                    }
                }
            } header: {
                Text(L("Project folders"))
            } footer: {
                Text(L("Dustpan looks inside these for build output such as node_modules, Flutter build folders and Cargo targets. Changes apply on the next scan."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L("Add")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !model.projectRoots.contains(url) {
            model.projectRoots.append(url)
        }
    }
}
