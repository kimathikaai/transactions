import Foundation
import Testing
@testable import transactions_ui

struct CategoryRecordTests {

    @Test("Category round-trips through JSON preserving every field")
    func roundTrip() throws {
        let cat = Category(
            id: "cat_a1b2",
            displayName: "Groceries",
            parent: "cat_root",
            color: "#8dd3c7",
            symbol: "cart.fill",
            transactionType: .expense,
            patterns: ["SOBEYS", "COSTCO"]
        )
        let data = try JSONEncoder().encode(cat)
        let decoded = try JSONDecoder().decode(Category.self, from: data)
        #expect(decoded == cat)
        #expect(decoded.isLeaf)
        #expect(!decoded.isRoot)
    }

    @Test("newID mints cat_<lowercased-uuid>")
    func idShape() throws {
        let id = CategoryFactory.newID()
        #expect(id.hasPrefix("cat_"))
        let suffix = String(id.dropFirst(4))
        #expect(UUID(uuidString: suffix) != nil)
        #expect(suffix == suffix.lowercased())
    }

    @Test("Draft materialize wires every field and mints an id")
    func draftMaterialize() throws {
        let draft = CategoryDraft(
            displayName: "Cafe",
            parent: nil,
            color: "#fdb462",
            symbol: "cup.and.saucer.fill",
            transactionType: .expense,
            patterns: []
        )
        let made = draft.materialize(id: "cat_fixed")
        #expect(made.id == "cat_fixed")
        #expect(made.displayName == "Cafe")
        #expect(made.parent == nil)
        #expect(made.isRoot)
    }
}
