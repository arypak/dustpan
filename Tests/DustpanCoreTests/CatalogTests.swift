import Foundation
import Testing
@testable import DustpanCore

@Suite("Catalog")
struct CatalogTests {
    @Test("Rule ids are unique kebab-case")
    func ids() {
        let ids = Catalog.rules.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil, "\(id)")
        }
    }

    @Test("Every rule explains itself in full sentences")
    func copy() {
        for rule in Catalog.rules {
            #expect(!rule.englishName.isEmpty)
            #expect(rule.englishSummary.hasSuffix("."), "\(rule.id) summary")
            #expect(rule.englishAftermath.hasSuffix("."), "\(rule.id) aftermath")
        }
    }

    @Test("Location rules have locations, and patterns are absolute or home-relative")
    func locations() {
        for rule in Catalog.rules {
            if rule.discovery == .locations {
                #expect(!rule.locations.isEmpty, "\(rule.id) has nowhere to look")
            }
            for location in rule.locations {
                #expect(location.pattern.hasPrefix("~/") || location.pattern.hasPrefix("/"), "\(rule.id): \(location.pattern)")
            }
        }
    }

    @Test("Nothing a rule points at is refused by the safety guard")
    func guardAgreesWithRules() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let safety = SafetyGuard(home: home)
        let resolver = PathResolver(home: home)
        for rule in Catalog.rules where rule.cleanup.isTrash {
            for location in rule.locations where location.mode == .item && !location.pattern.contains("*") {
                let url = URL(fileURLWithPath: resolver.expandTilde(location.pattern))
                #expect(safety.refusal(for: url) == nil, "\(rule.id) points at a protected path: \(location.pattern)")
            }
        }
    }

    @Test("Catch-all rules look at children, never a whole folder")
    func catchAlls() {
        for rule in Catalog.rules where rule.isCatchAll {
            #expect(rule.locations.allSatisfy { $0.mode == .children }, "\(rule.id)")
        }
    }

    @Test("Rules that reach into private folders say so")
    func fullDiskAccess() {
        #expect(Catalog.rule(id: "sandboxed-app-caches")?.needsFullDiskAccess == true)
        #expect(Catalog.rule(id: "device-backups")?.needsFullDiskAccess == true)
        #expect(Catalog.rule(id: "uv-cache")?.needsFullDiskAccess == false)
    }
}
