import DustpanCore
import Foundation

/// The shape of `dustpan scan --json`. Sizes are in bytes, dates are ISO 8601.
struct JSONReport: Encodable {
    struct Disk: Encodable {
        let volume: String
        let totalBytes: Int64
        let availableBytes: Int64
        let purgeableBytes: Int64
    }

    struct Item: Encodable {
        let path: String
        let label: String
        let bytes: Int64
        let modified: Date?
        let detail: String?
        let command: String?
    }

    struct Entry: Encodable {
        let id: String
        let name: String
        let category: String
        let safety: String
        let bytes: Int64
        let cleanup: String
        let command: String?
        let locked: Bool
        let summary: String
        let aftermath: String
        let items: [Item]
    }

    let version = Dustpan.version
    let scannedAt: Date
    let durationSeconds: Double
    let fullDiskAccess: Bool
    let disk: Disk?
    let trashBytes: Int64?
    let findings: [Entry]

    init(_ report: ScanReport) {
        scannedAt = report.startedAt
        durationSeconds = (report.duration * 10).rounded() / 10
        fullDiskAccess = report.hasFullDiskAccess
        disk = report.disk.map {
            Disk(volume: $0.volumeName, totalBytes: $0.total, availableBytes: $0.available, purgeableBytes: $0.purgeable)
        }
        trashBytes = report.trashBytes
        findings = report.findings.map { finding in
            let (cleanup, command): (String, String?) = switch finding.rule.cleanup {
            case .trash: ("trash", nil)
            case .command(let command): ("command", command)
            case .manual: ("manual", finding.rule.cleanup.localizedSteps)
            }
            return Entry(
                id: finding.rule.id, name: finding.rule.name, category: finding.rule.category.rawValue,
                safety: finding.rule.safety.rawValue, bytes: finding.bytes, cleanup: cleanup, command: command,
                locked: finding.locked, summary: finding.rule.summary, aftermath: finding.rule.aftermath,
                items: finding.targets.map {
                    Item(path: $0.url.path, label: $0.label, bytes: $0.bytes, modified: $0.modified, detail: $0.detail, command: $0.command)
                }
            )
        }
    }

    func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
