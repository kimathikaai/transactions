import Foundation
import Testing
@testable import transactions_ui

struct CategoryLookupTests {

    private func fixture() -> [transactions_ui.Category] {
        [
            transactions_ui.Category(id: "cat_food",  displayName: "Food",       parent: nil,
                     color: "#8dd3c7", symbol: "fork.knife",
                     transactionType: .expense, patterns: []),
            transactions_ui.Category(id: "cat_gro",   displayName: "Groceries",  parent: "cat_food",
                     color: "#8dd3c7", symbol: "cart.fill",
                     transactionType: .expense, patterns: ["SOBEYS", "COSTCO"]),
            transactions_ui.Category(id: "cat_din",   displayName: "Dining",     parent: "cat_food",
                     color: "#8dd3c7", symbol: "cup.and.saucer.fill",
                     transactionType: .expense, patterns: ["MCDONALD"]),
            transactions_ui.Category(id: "cat_tin",   displayName: "Transfer In",  parent: nil,
                     color: "#aec6cf", symbol: "arrow.down.circle.fill",
                     transactionType: .transfer_in, patterns: []),
            transactions_ui.Category(id: "cat_tout",  displayName: "Transfer Out", parent: nil,
                     color: "#aec6cf", symbol: "arrow.up.circle.fill",
                     transactionType: .transfer_out, patterns: []),
            transactions_ui.Category(id: "cat_orphan", displayName: "Orphan",    parent: "cat_missing",
                     color: "#000000", symbol: "questionmark",
                     transactionType: .expense, patterns: ["ORPHAN"]),
        ]
    }

    @Test("children returns direct children only")
    func children() {
        let cats = fixture()
        let ch = CategoryLookup.children(of: "cat_food", in: cats)
        #expect(ch.map { $0.id }.sorted() == ["cat_din", "cat_gro"])
    }

    @Test("firstRoot picks the first matching root by TransactionType")
    func firstRoot() {
        let cats = fixture()
        let type1: TransactionType = .transfer_in
        let type2: TransactionType = .transfer_out
        let type3: TransactionType = .expense
        #expect(CategoryLookup.firstRoot(ofType: type1, in: cats)?.id == "cat_tin")
        #expect(CategoryLookup.firstRoot(ofType: type2, in: cats)?.id == "cat_tout")
        #expect(CategoryLookup.firstRoot(ofType: type3, in: cats)?.id == "cat_food")
    }

    @Test("rules flattens leaves' patterns and skips orphan leaves")
    func rules() {
        let cats = fixture()
        let rs = CategoryLookup.rules(from: cats)
        #expect(rs.count == 3) // SOBEYS, COSTCO, MCDONALD; orphan skipped
        let sobeys = rs.first { $0.pattern == "SOBEYS" }
        #expect(sobeys?.category.rawValue == "cat_food")
        #expect(sobeys?.subcategory.rawValue == "cat_gro")
        let expenseType: TransactionType = .expense
        #expect(sobeys?.txType == expenseType)
    }

    @Test("coerceCategory snaps a transfer type to its transfer root and clears subcategory")
    func coerceTransferSnapsToRoot() {
        let cats = fixture()
        // A transfer type ignores whatever category/subcategory was passed and snaps.
        let inResult = CategoryLookup.coerceCategory(
            for: .transfer_in,
            category: CategoryID(rawValue: "cat_food"),
            subcategory: SubcategoryID(rawValue: "cat_gro"),
            in: cats
        )
        #expect(inResult.category?.rawValue == "cat_tin")
        #expect(inResult.subcategory == nil)

        let outResult = CategoryLookup.coerceCategory(
            for: .transfer_out,
            category: nil,
            subcategory: nil,
            in: cats
        )
        #expect(outResult.category?.rawValue == "cat_tout")
        #expect(outResult.subcategory == nil)
    }

    @Test("coerceCategory strips a transfer category from an expense/income type")
    func coerceStripsTransferFromNonTransfer() {
        let cats = fixture()
        let result = CategoryLookup.coerceCategory(
            for: .expense,
            category: CategoryID(rawValue: "cat_tin"),
            subcategory: nil,
            in: cats
        )
        #expect(result.category == nil)
        #expect(result.subcategory == nil)
    }

    @Test("coerceCategory leaves a normal category untouched on a non-transfer type")
    func coercePassesThroughNormalCategory() {
        let cats = fixture()
        let result = CategoryLookup.coerceCategory(
            for: .expense,
            category: CategoryID(rawValue: "cat_food"),
            subcategory: SubcategoryID(rawValue: "cat_gro"),
            in: cats
        )
        #expect(result.category?.rawValue == "cat_food")
        #expect(result.subcategory?.rawValue == "cat_gro")
    }
}
