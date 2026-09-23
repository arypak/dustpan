import DustpanCore
import SwiftUI

struct CategoryView: View {
    @Environment(AppModel.self) private var model
    let category: RuleCategory

    var body: some View {
        let findings = model.findings(in: category)
        let safe = model.cleanableBytes(.safe, in: category)
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        SizeText(bytes: model.bytes(in: category), font: .largeTitle.weight(.semibold))
                        let items = findings.reduce(0) { $0 + $1.targets.count }
                        Text("\(items) item\(items == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if safe > 0 {
                        Button("Select Safe (\(Format.bytes(safe)))") { model.select(.safe, in: category) }
                    }
                }
                .padding(.vertical, 4)
            }
            ForEach(findings) { finding in
                FindingSection(finding: finding)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category.title)
    }
}

private struct FindingSection: View {
    @Environment(AppModel.self) private var model
    let finding: Finding

    var body: some View {
        let rule = finding.rule
        let expanded = model.isOpen(finding)
        Section {
            header
            if finding.locked {
                HStack {
                    Label("Dustpan needs Full Disk Access to look here.", systemImage: "lock")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Privacy Settings") { SystemActions.openFullDiskAccessSettings() }
                }
            } else if finding.targets.count == 1 && finding.targets[0].command == nil {
                TargetRow(finding: finding, target: finding.targets[0], showsCheckbox: false)
            } else if expanded || !finding.isCleanable {
                ForEach(finding.targets) { target in
                    TargetRow(finding: finding, target: target, showsCheckbox: model.isSelectable(finding))
                }
            }
            switch rule.cleanup {
            case .command(let command) where finding.targets.allSatisfy({ $0.command == nil }):
                CommandRow(command: command)
            case .manual(let steps):
                Label(steps, systemImage: "hand.point.up.left")
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        } footer: {
            footer(rule)
        }
    }

    private var header: some View {
        let rule = finding.rule
        let expanded = model.isOpen(finding)
        return HStack(alignment: .center, spacing: 10) {
            if model.isSelectable(finding) {
                Checkbox(state: model.state(of: finding)) { model.toggle(finding) }
            } else {
                Image(systemName: finding.locked ? "lock.fill" : "terminal")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .help(finding.locked ? "Needs Full Disk Access" : "Dustpan leaves this to the tool that owns it")
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(rule.name).font(.headline)
                    SafetyBadge(safety: rule.safety)
                }
                Text(rule.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !finding.locked {
                SizeText(bytes: finding.bytes, font: .title3.weight(.semibold))
            }
            if model.isSelectable(finding) && finding.targets.count > 1 {
                Button {
                    withAnimation(.snappy) { model.toggleOpen(finding) }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(finding.targets.count) items")
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func footer(_ rule: Rule) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rule.aftermath)
            if !rule.quitFirst.isEmpty {
                Text("Quit \(rule.quitFirst.joined(separator: ", ")) first.")
            }
            if let note = rule.note {
                Text(note)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TargetRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    let target: Target
    let showsCheckbox: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            if showsCheckbox {
                Checkbox(state: model.selection.contains(target.id) ? .on : .off) { model.toggle(target) }
                    .padding(.leading, 22)
            } else {
                // Line up with the title above, which sits after a checkbox or an icon.
                Spacer().frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(target.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = target.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let command = target.command {
                    CommandRow(command: command)
                }
            }
            Spacer(minLength: 12)
            SizeText(bytes: target.bytes)
                .foregroundStyle(.secondary)
            Button {
                SystemActions.reveal(target.url)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.35)
            .help("Show in Finder")
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Show in Finder") { SystemActions.reveal(target.url) }
            Button("Copy Path") { SystemActions.copy(target.url.path) }
        }
    }
}
