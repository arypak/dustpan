import DustpanCore
import SwiftUI

struct CategoryView: View {
    @Environment(AppModel.self) private var model
    let category: RuleCategory

    var body: some View {
        let findings = model.findings(in: category)
        let safe = model.cleanableBytes(.safe, in: category)
        let items = findings.reduce(0) { $0 + $1.targets.count }
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        SizeText(bytes: model.bytes(in: category), font: .largeTitle.weight(.semibold))
                        Text(items == 1 ? L("1 item") : L("%@ items", String(items)))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if safe > 0 {
                        Button(L("Select Safe (%@)", Format.bytes(safe))) { model.select(.safe, in: category) }
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
        Section {
            header
            if finding.locked {
                HStack {
                    Label(L("Dustpan needs Full Disk Access to look here."), systemImage: "lock")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Open Privacy Settings")) { SystemActions.openFullDiskAccessSettings() }
                }
            } else if !model.isRevealed(finding) {
                HStack {
                    Label(L("Hidden until you ask: these may be files or tools you still use."), systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Show Items…")) { model.requestReveal(finding) }
                }
            } else {
                items
                switch rule.cleanup {
                case .command(let command) where finding.targets.allSatisfy({ $0.command == nil }):
                    CommandRow(command: command)
                case .manual:
                    Label(rule.cleanup.localizedSteps ?? "", systemImage: "hand.point.up.left")
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
        } footer: {
            footer(rule)
        }
    }

    @ViewBuilder
    private var items: some View {
        if finding.targets.count == 1 && finding.targets[0].command == nil {
            TargetRow(finding: finding, target: finding.targets[0], showsCheckbox: false)
        } else if model.isOpen(finding) || !finding.isCleanable {
            ForEach(finding.targets) { target in
                TargetRow(finding: finding, target: target, showsCheckbox: model.isSelectable(finding))
            }
        }
    }

    private var header: some View {
        let rule = finding.rule
        return HStack(alignment: .center, spacing: 10) {
            if model.isSelectable(finding) {
                Checkbox(state: model.state(of: finding)) { model.toggle(finding) }
            } else {
                Image(systemName: finding.locked ? "lock.fill" : !model.isRevealed(finding) ? "eye.slash" : "terminal")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .help(finding.locked ? L("Needs Full Disk Access")
                          : !model.isRevealed(finding) ? L("Asks before opening")
                          : L("The tool that owns this should clean it"))
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
                        Text(L("%@ items", String(finding.targets.count)))
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(model.isOpen(finding) ? 90 : 0))
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
                Text(L("Quit first: %@.", rule.quitFirst.joined(separator: ", ")))
            }
            if let note = rule.note {
                Text(note)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
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
            .help(L("Show in Finder"))
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button(L("Show in Finder")) { SystemActions.reveal(target.url) }
            Button(L("Copy Path")) { SystemActions.copy(target.url.path) }
        }
    }
}
