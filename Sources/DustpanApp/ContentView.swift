import DustpanCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 340)
        } detail: {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.report != nil { SelectionBar() }
                }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.phase == .scanning || model.phase == .cleaning {
                    ProgressView().controlSize(.small).padding(.horizontal, 6)
                } else {
                    Button { model.scan() } label: { Label(L("Scan Again"), systemImage: "arrow.clockwise") }
                        .help(L("Scan again (⌘R)"))
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { model.sheet != nil },
            set: { if !$0 { model.finishSweep() } }
        )) {
            switch model.sheet {
            case .result: ResultSheet()
            default: ConfirmSheet()
            }
        }
        .alert(
            L("Show items you may still need?"),
            isPresented: Binding(get: { model.pendingReveal != nil }, set: { if !$0 { model.pendingReveal = nil } })
        ) {
            Button(L("Cancel"), role: .cancel) { model.pendingReveal = nil }
            Button(L("Show")) { model.confirmReveal() }
        } message: {
            Text(revealMessage)
        }
        .onAppear { model.applyAppearance() }
        .task {
            if model.phase == .idle { model.scan() }
            await Snapshots.runIfRequested(model)
            await UITest.runIfRequested(model)
        }
    }

    private var revealMessage: String {
        switch model.pendingReveal {
        case .category(let category):
            L("“%@” lists things you may still need, such as your apps, virtual machines, personal files or tools. Nothing moves until you confirm again.", category.title)
        case .finding(let id):
            L("“%@” may hold files or tools you still use. Nothing moves until you confirm again.",
              model.findings.first { $0.id == id }?.rule.name ?? id)
        case nil:
            ""
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.report == nil {
            ScanningView()
        } else {
            switch model.sidebar ?? .overview {
            case .overview:
                OverviewView()
            case .category(let category):
                CategoryView(category: category)
            }
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let categories = model.report == nil ? RuleCategory.allCases : model.categoriesWithFindings
        List(selection: Binding(get: { model.sidebar }, set: { model.navigate(to: $0) })) {
            Label(L("Overview"), systemImage: "gauge.with.dots.needle.33percent")
                .tag(SidebarItem.overview)
            Section(L("Found on this Mac")) {
                // Loop over SidebarItem itself: List tags each row with its ForEach id, and a
                // Category id wouldn't match the SidebarItem selection, so clicks would select nothing.
                ForEach(categories.map { SidebarItem.category($0) }, id: \.self) { item in
                    if case .category(let category) = item {
                        HStack(spacing: 6) {
                            Label(category.title, systemImage: category.symbol)
                            Spacer(minLength: 4)
                            if model.asksBeforeOpening(category) {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .help(L("Asks before opening"))
                                    .accessibilityLabel(L("Asks before opening"))
                            }
                        }
                        .badge(model.report == nil ? Text("") : Text(Format.bytes(model.bytes(in: category))).monospacedDigit())
                        .disabled(model.report == nil)
                        .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            Text(L("Looking around your Mac…"))
                .font(.title2.weight(.semibold))
            VStack(spacing: 6) {
                ProgressView(value: model.progress?.fraction ?? 0)
                    .frame(width: 280)
                Text(model.progress?.current ?? L("Getting started"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(L("Nothing is changed while Dustpan looks."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.selectedTargets.count
        HStack(spacing: 14) {
            if count > 0 {
                Text(count == 1 ? L("1 item selected") : L("%@ items selected", String(count)))
                    .foregroundStyle(.secondary)
                Button(L("Clear")) { model.selection.removeAll() }
                    .buttonStyle(.link)
            } else {
                Text(L("Tick what you want to sweep. Everything goes to the Trash, nothing is deleted."))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if count > 0 {
                SizeText(bytes: model.selectedBytes, font: .title3.weight(.semibold))
            }
            Button {
                model.sheet = .confirm
            } label: {
                Label(L("Move to Trash…"), systemImage: "trash")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(count == 0 || model.phase != .ready)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
