import AppKit
import DustpanCore
import SwiftUI

extension Safety {
    var color: Color {
        switch self {
        case .safe: .green
        case .caution: .orange
        case .review: .purple
        }
    }
}

struct SafetyBadge: View {
    let safety: Safety

    var body: some View {
        Text(Localization.uppercased(safety.title))
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(safety.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(safety.color.opacity(0.14), in: Capsule())
            .help(safety.explanation)
    }
}

struct SizeText: View {
    let bytes: Int64
    var font: Font = .body

    var body: some View {
        Text(Format.bytes(bytes))
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

/// A native checkbox that can show a mixed state, for "some of these are selected".
struct Checkbox: NSViewRepresentable {
    var state: NSControl.StateValue
    var action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.clicked))
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.allowsMixedState = state == .mixed
        button.state = state
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func clicked(_ sender: NSButton) { action() }
    }
}

/// A horizontal bar that splits the disk into what's used, what Dustpan found, and what's free.
struct CapacityBar: View {
    struct Segment: Identifiable {
        let id: String
        let bytes: Int64
        let color: Color
    }

    let total: Int64
    let segments: [Segment]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1.5) {
                ForEach(segments.filter { $0.bytes > 0 }) { segment in
                    Rectangle()
                        .fill(segment.color.gradient)
                        .frame(width: max(2, geometry.size.width * CGFloat(segment.bytes) / CGFloat(max(total, 1))))
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(height: 16)
    }
}

struct LegendDot: View {
    let color: Color
    let title: String
    let bytes: Int64

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.secondary)
            SizeText(bytes: bytes).fontWeight(.medium)
        }
        .font(.callout)
    }
}

/// A translated sentence with one `%@`, the value set in semibold.
func emphasized(_ template: String, _ value: String) -> Text {
    let parts = template.components(separatedBy: "%@")
    guard parts.count == 2 else { return Text(template.replacingOccurrences(of: "%@", with: value)) }
    return Text(parts[0]) + Text(value).fontWeight(.semibold) + Text(parts[1])
}

/// A command the user should run themselves, with a copy button.
struct CommandRow: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                SystemActions.copy(command)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            } label: {
                Label(copied ? L("Copied") : L("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}
