import DustpanCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let disk = model.report?.disk {
                    DiskCard(disk: disk)
                }
                if model.report?.lockedFindings.isEmpty == false {
                    AccessCard()
                }
                QuickSweepCard()
                Text(L("Where the space went"))
                    .font(.title3.weight(.semibold))
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach(model.categoriesWithFindings) { category in
                        CategoryCard(category: category)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(L("Overview"))
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

private struct DiskCard: View {
    @Environment(AppModel.self) private var model
    let disk: DiskInfo

    var body: some View {
        let safe = model.cleanableBytes(.safe)
        let caution = model.cleanableBytes(.caution)
        let review = model.cleanableBytes(.review)
        let found = safe + caution + review
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label(disk.volumeName, systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                SizeText(bytes: disk.available, font: .title2.weight(.semibold))
                Text(L("free")).foregroundStyle(.secondary)
            }
            CapacityBar(total: disk.total, segments: [
                .init(id: "other", bytes: max(0, disk.used - found), color: .gray),
                .init(id: "review", bytes: review, color: Safety.review.color),
                .init(id: "caution", bytes: caution, color: Safety.caution.color),
                .init(id: "safe", bytes: safe, color: Safety.safe.color),
            ])
            HStack(spacing: 18) {
                LegendDot(color: .gray, title: L("Everything else"), bytes: max(0, disk.used - found))
                LegendDot(color: Safety.safe.color, title: Safety.safe.title, bytes: safe)
                LegendDot(color: Safety.caution.color, title: Safety.caution.title, bytes: caution)
                LegendDot(color: Safety.review.color, title: Safety.review.title, bytes: review)
            }
            if disk.purgeable > 1_000_000_000 || model.sweptBytes > 0 {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    if model.sweptBytes > 0 {
                        Label {
                            Text(L("You've moved %@ to the Trash. Empty it in Finder to get the space back.", Format.bytes(model.sweptBytes)))
                        } icon: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                    }
                    if disk.purgeable > 1_000_000_000 {
                        Label {
                            Text(L("macOS can also free %@ of purgeable space on its own when it needs to.", Format.bytes(disk.purgeable)))
                        } icon: {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AccessCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let locked = model.report?.lockedFindings ?? []
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Some places are hidden from Dustpan"))
                        .font(.headline)
                    Text(L("macOS keeps %@ private until you give Dustpan Full Disk Access. Dustpan only reads sizes; it still asks before moving anything.",
                           locked.map(\.rule.name).joined(separator: ", ")))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("After you turn it on, reopen the app so macOS applies it."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(L("Open Privacy Settings")) { SystemActions.openFullDiskAccessSettings() }
                        Button(L("Reopen Dustpan")) { SystemActions.relaunch() }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

private struct QuickSweepCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let safe = model.cleanableBytes(.safe)
        Card {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Safety.safe.color)
                VStack(alignment: .leading, spacing: 4) {
                    emphasized(L("%@ of caches and build output grows back on its own"), Format.bytes(safe))
                        .font(.title3)
                    Text(L("Package caches, build folders, logs and leftovers. Apps and tools recreate them when they need them."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Select All Safe")) { model.select(.safe) }
                    .controlSize(.large)
                    .disabled(safe == 0)
            }
        }
    }
}

private struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let category: RuleCategory

    var body: some View {
        let findings = model.findings(in: category)
        Button {
            model.navigate(to: .category(category))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: category.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer()
                    SizeText(bytes: model.bytes(in: category), font: .title2.weight(.semibold))
                }
                Text(category.title)
                    .font(.headline)
                Text(findings.prefix(3).map(\.rule.name).joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                HStack(spacing: 6) {
                    ForEach(Safety.allCases, id: \.self) { safety in
                        let count = String(findings.filter { $0.rule.safety == safety }.count)
                        if count != "0" {
                            Text(safety == .safe ? L("%@ safe", count) : safety == .caution ? L("%@ caution", count) : L("%@ review", count))
                                .font(.caption)
                                .foregroundStyle(safety.color)
                        }
                    }
                    Spacer()
                    if model.asksBeforeOpening(category) {
                        Label(L("Asks first"), systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
