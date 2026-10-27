import Foundation
import Testing
@testable import transactions_ui

struct CategoryValidatorTests {

    private func root(_ id: String, _ name: String, _ type: TransactionType = .expense) -> transactions_ui.Category {
        transactions_ui.Category(id: id, displayName: name, parent: nil,
                 color: "#000", symbol: "folder", transactionType: type, patterns: [])
    }
    private func leaf(_ id: String, _ name: String, _ parent: String, _ type: TransactionType = .expense) -> transactions_ui.Category {
        transactions_ui.Category(id: id, displayName: name, parent: parent,
                 color: "#000", symbol: "folder", transactionType: type, patterns: [])
    }
    private func edit(cat: String? = nil, sub: String? = nil) -> TransactionEdit {
        TransactionEdit(
            category: cat.map { CategoryID(rawValue: $0) },
            subcategory: sub.map { SubcategoryID(rawValue: $0) }
        )
    }

    @Test("Clean catalog + matching edits → empty result")
    func clean() {
        let cats = [root("cat_food", "Food"), leaf("cat_gro", "Groceries", "cat_food")]
        let edits = ["h1": edit(cat: "cat_food", sub: "cat_gro")]
        // A single transaction with matching hash → no stale ref.
        let txs = [Transaction(contentHash: "h1", date: .init(), details: "", debit: 0, credit: 0,
                               transactionType: .expense, accountID: UUID())]
        let r = CategoryValidator.validate(categories: cats, edits: edits, transactions: txs)
        #expect(r.brokenEdits.isEmpty)
        #expect(r.structuralViolations.isEmpty)
        #expect(r.staleRefs.isEmpty)
    }

    @Test("Edit pointing at missing category id → brokenEdits entry")
    func brokenCategoryEdit() {
        let cats = [root("cat_food", "Food")]
        let edits = ["h1": edit(cat: "cat_ghost")]
        let r = CategoryValidator.validate(categories: cats, edits: edits, transactions: [])
        #expect(r.brokenEdits.count == 1)
        #expect(r.brokenEdits[0].field == .category)
        #expect(r.brokenEdits[0].referencedID == "cat_ghost")
    }

    @Test("Leaf whose parent missing → orphanLeaf violation")
    func orphanLeaf() {
        let cats = [leaf("cat_gro", "Groceries", "cat_missing")]
        let r = CategoryValidator.validate(categories: cats, edits: [:], transactions: [])
        #expect(r.structuralViolations.contains { $0.kind == .orphanLeaf && $0.categoryID == "cat_gro" })
    }

    @Test("Leaf whose parent is itself a leaf → parentIsLeaf violation")
    func parentIsLeaf() {
        let cats = [root("cat_food", "Food"),
                    leaf("cat_gro", "Groceries", "cat_food"),
                    leaf("cat_org", "Organic", "cat_gro")] // depth-3 attempt
        let r = CategoryValidator.validate(categories: cats, edits: [:], transactions: [])
        #expect(r.structuralViolations.contains { $0.kind == .parentIsLeaf && $0.categoryID == "cat_org" })
    }

    @Test("Leaf transactionType != parent → transactionTypeMismatch violation")
    func typeMismatch() {
        let cats = [root("cat_food", "Food", .expense),
                    leaf("cat_gro", "Groceries", "cat_food", .income)]
        let r = CategoryValidator.validate(categories: cats, edits: [:], transactions: [])
        #expect(r.structuralViolations.contains { $0.kind == .transactionTypeMismatch && $0.categoryID == "cat_gro" })
    }

    @Test("Duplicate displayName across records → one violation per duplicated record")
    func dupNames() {
        let cats = [root("cat_a", "Same"), root("cat_b", "Same"), root("cat_c", "Other")]
        let r = CategoryValidator.validate(categories: cats, edits: [:], transactions: [])
        let dups = r.structuralViolations.filter { $0.kind == .duplicateDisplayName }
        #expect(dups.count == 2)
        #expect(Set(dups.map(\.categoryID)) == ["cat_a", "cat_b"])
    }

    @Test("Edit whose contentHash matches no transaction → staleRefs entry")
    func staleRefs() {
        let cats = [root("cat_food", "Food")]
        let edits = ["dead": edit(cat: "cat_food"), "alive": edit(cat: "cat_food")]
        let txs = [Transaction(contentHash: "alive", date: .init(), details: "", debit: 0, credit: 0,
                               transactionType: .expense, accountID: UUID())]
        let r = CategoryValidator.validate(categories: cats, edits: edits, transactions: txs)
        #expect(r.staleRefs.map(\.contentHash) == ["dead"])
    }
}
