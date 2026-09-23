import DustpanCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
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
                    Button { model.scan() } label: { Label("Scan Again", systemImage: "arrow.clockwise") }
                        .help("Scan again (⌘R)")
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
        .task {
            if model.phase == .idle { model.scan() }
            await Snapshots.runIfRequested(model)
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
        @Bindable var model = model
        List(selection: $model.sidebar) {
            NavigationLink(value: SidebarItem.overview) {
                Label("Overview", systemImage: "gauge.with.dots.needle.33percent")
            }
            Section("Found on this Mac") {
                ForEach(model.report == nil ? RuleCategory.allCases : model.categoriesWithFindings) { category in
                    NavigationLink(value: SidebarItem.category(category)) {
                        Label(category.title, systemImage: category.symbol)
                    }
                    .badge(model.report == nil ? Text("") : Text(Format.bytes(model.bytes(in: category))).monospacedDigit())
                    .disabled(model.report == nil)
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
            Text("Looking around your Mac…")
                .font(.title2.weight(.semibold))
            VStack(spacing: 6) {
                ProgressView(value: model.progress?.fraction ?? 0)
                    .frame(width: 280)
                Text(model.progress?.current ?? "Getting started")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("Nothing is changed while Dustpan looks.")
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
                Text("\(count) item\(count == 1 ? "" : "s") selected")
                    .foregroundStyle(.secondary)
                Button("Clear") { model.selection.removeAll() }
                    .buttonStyle(.link)
            } else {
                Text("Tick what you want to sweep. Everything goes to the Trash, nothing is deleted.")
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
                Label("Move to Trash…", systemImage: "trash")
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
