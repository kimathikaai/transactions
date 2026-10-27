import Foundation
import Testing
@testable import transactions_ui

/// Decodes the committed seed file and asserts its structural invariants.
/// The seed is the single source of truth for categories — the runtime read
/// path is CategoryLookup + CategoryStore.
struct CategorySeedDecodesTests {

    private var seedURL: URL {
        // #filePath => .../transactions-uiTests/CategorySeedDecodesTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // transactions-uiTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("transactions-ui/Data/demo/categories.json")
    }

    private func loadSeed() throws -> [transactions_ui.Category] {
        let data = try Data(contentsOf: seedURL)
        return try JSONDecoder().decode([transactions_ui.Category].self, from: data)
    }

    @Test("Seed decodes as [Category]")
    func decodes() throws {
        let cats = try loadSeed()
        #expect(!cats.isEmpty)
    }

    @Test("Every id has the cat_<uuid> shape and is unique")
    func idShape() throws {
        let cats = try loadSeed()
        var seen = Set<String>()
        for c in cats {
            #expect(c.id.hasPrefix("cat_"), "\(c.id) missing prefix")
            let suffix = String(c.id.dropFirst(4))
            #expect(UUID(uuidString: suffix) != nil, "\(c.id) not a uuid")
            #expect(!seen.contains(c.id), "duplicate id \(c.id)")
            seen.insert(c.id)
        }
    }

    @Test("displayName is globally unique across the whole catalog")
    func namesUnique() throws {
        let cats = try loadSeed()
        var seen = Set<String>()
        for c in cats {
            #expect(!seen.contains(c.displayName), "duplicate displayName \(c.displayName)")
            seen.insert(c.displayName)
        }
    }

    @Test("Every leaf's parent exists, is a root, and shares its transactionType")
    func parentIntegrity() throws {
        let cats = try loadSeed()
        let byID = Dictionary(uniqueKeysWithValues: cats.map { ($0.id, $0) })
        for c in cats where c.parent != nil {
            guard let parent = byID[c.parent!] else {
                Issue.record("leaf \(c.displayName) references missing parent \(c.parent!)")
                continue
            }
            #expect(parent.parent == nil, "\(c.displayName)'s parent is itself a leaf")
            #expect(parent.transactionType == c.transactionType,
                    "\(c.displayName) transactionType mismatch with parent")
        }
    }

    @Test("Roots have empty patterns; leaves may have patterns")
    func rootsHaveNoPatterns() throws {
        let cats = try loadSeed()
        for c in cats where c.parent == nil {
            #expect(c.patterns.isEmpty, "root \(c.displayName) unexpectedly has patterns")
        }
    }

    @Test("No pattern string is blank")
    func noBlankPatterns() throws {
        let cats = try loadSeed()
        for c in cats {
            for pattern in c.patterns {
                #expect(!pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "\(c.displayName) has a blank pattern (would match everything)")
            }
        }
    }

    @Test("No pattern is shared across leaves (auto-classification stays unambiguous)")
    func patternsAreUniqueAcrossLeaves() throws {
        let cats = try loadSeed()
        // Match-time is case-insensitive, so compare normalized to catch
        // patterns that would ambiguously claim the same rows across two leaves.
        var ownerByPattern: [String: String] = [:]
        for c in cats {
            for pattern in c.patterns {
                let key = pattern.lowercased()
                if let existing = ownerByPattern[key] {
                    Issue.record("pattern \"\(pattern)\" is claimed by both \(existing) and \(c.displayName)")
                } else {
                    ownerByPattern[key] = c.displayName
                }
            }
        }
    }
}
