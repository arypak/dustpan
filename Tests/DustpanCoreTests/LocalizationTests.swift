import Foundation
import Testing
@testable import DustpanCore

@Suite("Localization")
struct LocalizationTests {
    /// The package root, found from this file's location.
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every Swift source file except the translation table itself.
    static let sources: [String] = {
        let folder = root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Translations.swift" } ?? []
        return files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }()

    /// String literals passed to `L(…)`, `model.L(…)`, `say(…)` and `Localization.format(…)`.
    static let usedKeys: Set<String> = {
        let pattern = #"(?<![A-Za-z0-9_])(?:L|say|Localization\.format)\(\s*"((?:[^"\\]|\\.)*)""#
        let regex = try! NSRegularExpression(pattern: pattern)
        var keys = Set<String>()
        for source in sources {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                keys.insert(source[range].replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\"))
            }
        }
        return keys
    }()

    static var ruleTexts: [String] {
        Catalog.rules.flatMap { rule in
            [rule.englishName, rule.englishSummary, rule.englishAftermath, rule.englishNote, rule.cleanup.englishSteps].compactMap { $0 }
        }
    }

    @Test("The sources actually call L()")
    func scannerWorks() {
        #expect(Self.usedKeys.count > 100)
        #expect(Self.usedKeys.contains("Move to Trash…"))
    }

    @Test("Every text on screen has a Turkish translation")
    func noMissingTranslations() {
        let missing = (Self.usedKeys.union(Self.ruleTexts)).subtracting(Translations.turkish.keys).sorted()
        #expect(missing.isEmpty, "Missing Turkish for: \(missing)")
    }

    @Test("The table holds no translations nothing uses")
    func noUnusedTranslations() {
        let everything = Self.sources.joined(separator: "\n")
        let unused = Translations.turkish.keys.filter { key in
            let literal = "\"" + key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
            return !everything.contains(literal)
        }
        #expect(unused.isEmpty, "Unused translations: \(unused.sorted())")
    }

    @Test("Translations keep their placeholders")
    func placeholders() throws {
        let regex = try NSRegularExpression(pattern: #"%(?:\d+\$)?@"#)
        func count(_ text: String) -> Int { regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) }
        for (key, value) in Translations.turkish {
            #expect(count(key) == count(value), "\(key) → \(value)")
        }
    }

    @Test("Turkish numbers, dates and capitals")
    func turkishFormatting() {
        let now = Date()
        #expect(Format.bytes(11_400_000_000, language: .turkish) == "11,4 GB")
        #expect(Format.bytes(512, language: .turkish) == "512 bayt")
        #expect(Format.relative(now.addingTimeInterval(-86_400 * 21), now: now, language: .turkish) == "3 hafta önce")
        #expect(Localization.uppercased("İncele", in: .turkish) == "İNCELE")
        #expect(Localization.uppercased("Güvenli", in: .turkish) == "GÜVENLİ")
        #expect(Localization.lowercased("İncele", in: .turkish) == "incele")
        #expect(Localization.format("Move %@ to the Trash?", ["2 GB"], in: .turkish) == "2 GB Çöp Sepetine taşınsın mı?")
    }

    @Test("Picks the first preferred language Dustpan speaks")
    func languageMatching() {
        #expect(Language.matching(["tr-TR", "en-US"]) == .turkish)
        #expect(Language.matching(["de-DE", "en-GB"]) == .english)
        #expect(Language.matching(["de-DE", "fr-FR"]) == nil)
    }
}
