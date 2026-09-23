import DustpanCore
import SwiftUI

struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = model.selectedGroups
        let apps = model.appsToQuit
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Move \(Format.bytes(model.selectedBytes)) to the Trash?")
                        .font(.title2.weight(.semibold))
                    Text("Nothing is deleted yet. Everything waits in the Trash, where you can put it back, until you empty it.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            List {
                ForEach(groups, id: \.finding.id) { group in
                    HStack {
                        Circle().fill(group.finding.rule.safety.color).frame(width: 8, height: 8)
                        Text(group.finding.rule.name)
                        if group.targets.count > 1 {
                            Text("\(group.targets.count) items").foregroundStyle(.secondary)
                        }
                        Spacer()
                        SizeText(bytes: group.targets.reduce(0) { $0 + $1.bytes })
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: min(260, CGFloat(groups.count) * 28 + 12))

            if !apps.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    (Text("Quit these first: ").fontWeight(.medium) + Text(apps.map { $0.running ? "\($0.name) (running)" : $0.name }.joined(separator: ", ")))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }

            HStack {
                if model.phase == .cleaning {
                    ProgressView().controlSize(.small)
                    Text("Moving to the Trash…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.finishSweep() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    Task { await model.clean() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .disabled(model.phase == .cleaning)
        }
        .padding(24)
        .frame(width: 520)
    }
}

struct ResultSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let result = model.result ?? CleanResult()
        let needsAdmin = result.failures.contains(where: \.needsAdmin)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(result.failures.isEmpty ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Moved \(Format.bytes(result.movedBytes)) to the Trash")
                        .font(.title2.weight(.semibold))
                    Text("Empty the Trash in Finder when you're sure, and the space is yours again.")
                        .foregroundStyle(.secondary)
                }
            }

            if !result.failures.isEmpty {
                Text("\(result.failures.count) item\(result.failures.count == 1 ? "" : "s") stayed where \(result.failures.count == 1 ? "it was" : "they were"):")
                    .font(.headline)
                List(result.failures, id: \.target.id) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(failure.target.label).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Show in Finder") { SystemActions.reveal(failure.target.url) }
                                .buttonStyle(.link)
                        }
                        Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(height: min(200, CGFloat(result.failures.count) * 44 + 12))
            }

            HStack {
                if needsAdmin {
                    Button("Try with Finder…") { Task { await model.retryWithFinder() } }
                        .help("Finder can ask for your password to move items that belong to the system")
                }
                Spacer()
                Button("Open Trash") { SystemActions.openTrash() }
                Button("Done") { model.finishSweep() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .disabled(model.phase == .cleaning)
    }
}
