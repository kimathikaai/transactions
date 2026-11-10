import Foundation
import Testing
@testable import transactions_ui

/// A nil category in an edit means "follow the rules" (the import-time pick),
/// unless the edit also overrides the type — then the rules' pick (matched against
/// the parsed type) no longer applies and the transaction is Uncategorized.
@Suite("Category follows rules")
struct CategoryFollowsRulesTests {

    private func makeVM(dir: TempDataDirectory) -> AppViewModel {
        AppViewModel(
            accountStore: AccountStore(fileURL: dir.file("accounts.json")),
            reserveStore: ReserveStore(fileURL: dir.file("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.file("reserveEvents.json")),
            editStore: EditStore(fileURL: dir.file("edits.json")),
            categoryStore: CategoryStore(fileURL: dir.file("categories.json")),
            reimbursementStore: ReimbursementStore(fileURL: dir.file("reimbursements.json")),
            csvDirectory: dir.file("csv")
        )
    }

    /// Food (with a Groceries leaf) and Fun, all expense — so `coerceCategory` keeps them.
    private func seedCategories(_ dir: TempDataDirectory) throws {
        let seed: [transactions_ui.Category] = [
            transactions_ui.Category(id: "cat_food", displayName: "Food", parent: nil,
                     color: "#8dd3c7", symbol: "fork.knife",
                     transactionType: .expense, patterns: []),
            transactions_ui.Category(id: "cat_gro", displayName: "Groceries", parent: "cat_food",
                     color: "#8dd3c7", symbol: "cart",
                     transactionType: .expense, patterns: []),
            transactions_ui.Category(id: "cat_fun", displayName: "Fun", parent: nil,
                     color: "#fb8072", symbol: "gamecontroller",
                     transactionType: .expense, patterns: []),
        ]
        try AtomicJSONFile.encoder().encode(seed).write(to: dir.file("categories.json"))
    }

    private func persistedEdit(_ dir: TempDataDirectory, _ hash: String) throws -> TransactionEdit? {
        let url = dir.file("edits.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let edits = try AtomicJSONFile.decoder().decode([String: TransactionEdit].self, from: Data(contentsOf: url))
        return edits[hash]
    }

    /// An expense the rules categorized as Food › Groceries.
    private func ruleCategorizedExpense(edit: TransactionEdit? = nil) -> Transaction {
        Transaction(
            contentHash: "hash-rules",
            date: Date(timeIntervalSince1970: 0),
            details: "GLOBEX GROCERS", debit: 40, credit: 0,
            transactionType: .expense,
            category: CategoryID(rawValue: "cat_food"),
            subcategory: SubcategoryID(rawValue: "cat_gro"),
            accountID: UUID(),
            edit: edit
        )
    }

    // MARK: - Reading

    @Test func notesOnlyEditFollowsRules() {
        let tx = ruleCategorizedExpense(edit: TransactionEdit(notes: "hi"))
        #expect(tx.effectiveCategory?.rawValue == "cat_food")
        #expect(tx.effectiveSubcategory?.rawValue == "cat_gro")
        #expect(tx.categorySource == .rule)
    }

    @Test func explicitCategoryOverrides() {
        let tx = ruleCategorizedExpense(edit: TransactionEdit(category: CategoryID(rawValue: "cat_fun")))
        #expect(tx.effectiveCategory?.rawValue == "cat_fun")
        #expect(tx.effectiveSubcategory == nil)
        #expect(tx.categorySource == .overridden)
    }

    @Test func typeOverrideWithNilCategoryIsUncategorized() {
        let tx = ruleCategorizedExpense(edit: TransactionEdit(transactionType: .income))
        #expect(tx.effectiveCategory == nil)
        #expect(tx.effectiveSubcategory == nil)
        #expect(tx.categorySource == .uncategorized)
    }

    // MARK: - Saving

    @Test func saveEditMatchingRulesStoresNilCategory() throws {
        let dir = TempDataDirectory()
        try seedCategories(dir)
        let vm = makeVM(dir: dir)
        let tx = ruleCategorizedExpense()
        #expect(vm.saveEdit(for: tx, category: CategoryID(rawValue: "cat_food"),
                            subcategory: SubcategoryID(rawValue: "cat_gro"), notes: "n"))
        let stored = try #require(try persistedEdit(dir, tx.contentHash))
        #expect(stored.category == nil)
        #expect(stored.subcategory == nil)
        #expect(stored.notes == "n")
    }

    @Test func saveEditSameTypeIsNotAnOverride() throws {
        let dir = TempDataDirectory()
        try seedCategories(dir)
        let vm = makeVM(dir: dir)
        let tx = ruleCategorizedExpense()
        #expect(vm.saveEdit(for: tx, category: CategoryID(rawValue: "cat_fun"), subcategory: nil,
                            notes: nil, transactionType: .expense))
        let stored = try #require(try persistedEdit(dir, tx.contentHash))
        #expect(stored.transactionType == nil)
        #expect(stored.category?.rawValue == "cat_fun")
    }

    @Test func saveEditEmptyResultRemovesRecord() throws {
        let dir = TempDataDirectory()
        try seedCategories(dir)
        let vm = makeVM(dir: dir)
        let tx = ruleCategorizedExpense()
        _ = vm.saveEdit(for: tx, category: CategoryID(rawValue: "cat_fun"), subcategory: nil, notes: nil)
        #expect(vm.rowCounts().edits == 1)
        #expect(vm.saveEdit(for: tx, category: CategoryID(rawValue: "cat_food"),
                            subcategory: SubcategoryID(rawValue: "cat_gro"), notes: nil))
        #expect(vm.rowCounts().edits == 0)
    }

    // MARK: - Intent helpers

    @Test func updateNotesKeepsOverride() throws {
        let dir = TempDataDirectory()
        try seedCategories(dir)
        let vm = makeVM(dir: dir)
        let tx = ruleCategorizedExpense()
        #expect(vm.updateClassification(for: tx, type: .expense,
                                        category: CategoryID(rawValue: "cat_fun"), subcategory: nil))
        let afterFirst = ruleCategorizedExpense(edit: try persistedEdit(dir, tx.contentHash))
        #expect(vm.updateNotes(for: afterFirst, notes: "x"))
        let stored = try #require(try persistedEdit(dir, tx.contentHash))
        #expect(stored.category?.rawValue == "cat_fun")
        #expect(stored.notes == "x")
    }

    @Test func updateClassificationKeepsNotes() throws {
        let dir = TempDataDirectory()
        try seedCategories(dir)
        let vm = makeVM(dir: dir)
        let tx = ruleCategorizedExpense(edit: TransactionEdit(notes: "keep"))
        #expect(vm.updateClassification(for: tx, type: .expense,
                                        category: CategoryID(rawValue: "cat_fun"), subcategory: nil))
        let stored = try #require(try persistedEdit(dir, tx.contentHash))
        #expect(stored.category?.rawValue == "cat_fun")
        #expect(stored.notes == "keep")
    }

    @Test func revertKeepsNotes() throws {
        let dir = TempDataDirectory()
        try seedCategories(dir)
        let vm = makeVM(dir: dir)
        let tx = ruleCategorizedExpense(edit: TransactionEdit(category: CategoryID(rawValue: "cat_fun"),
                                                              notes: "keep", transactionType: .income))
        #expect(vm.revertClassification(for: tx))
        let stored = try #require(try persistedEdit(dir, tx.contentHash))
        #expect(stored.category == nil)
        #expect(stored.transactionType == nil)
        #expect(stored.notes == "keep")
    }

    @Test func revertWithoutNotesRemovesRecord() throws {
        let dir = TempDataDirectory()
        try seedCategories(dir)
        let vm = makeVM(dir: dir)
        let tx = ruleCategorizedExpense()
        _ = vm.saveEdit(for: tx, category: CategoryID(rawValue: "cat_fun"), subcategory: nil, notes: nil)
        #expect(vm.rowCounts().edits == 1)
        let edited = ruleCategorizedExpense(edit: try persistedEdit(dir, tx.contentHash))
        #expect(vm.revertClassification(for: edited))
        #expect(vm.rowCounts().edits == 0)
    }

    // MARK: - Re-typing and the type lock

    @Test func retypeRuleExpenseToIncomeIsUncategorized() throws {
        let dir = TempDataDirectory()
        try seedCategories(dir)
        let vm = makeVM(dir: dir)
        let tx = ruleCategorizedExpense()
        // What CategorySection sends: the type change with the current (expense) pick.
        #expect(vm.updateClassification(for: tx, type: .income,
                                        category: CategoryID(rawValue: "cat_food"),
                                        subcategory: SubcategoryID(rawValue: "cat_gro")))
        let stored = try #require(try persistedEdit(dir, tx.contentHash))
        #expect(stored.transactionType == .income)
        #expect(stored.category == nil)
        #expect(ruleCategorizedExpense(edit: stored).effectiveCategory == nil)
    }

    /// An income re-typed to Expense, then reimbursed: the link locks the type.
    private func lockedRetypedExpense(_ vm: AppViewModel) -> Transaction {
        let tx = Transaction(
            contentHash: "hash-locked", date: Date(timeIntervalSince1970: 0),
            details: "GLOBEX REFUND", debit: 0, credit: 50,
            transactionType: .income, accountID: UUID(),
            edit: TransactionEdit(category: CategoryID(rawValue: "cat_fun"), transactionType: .expense)
        )
        let income = Transaction(
            contentHash: "hash-src", date: Date(timeIntervalSince1970: 0),
            details: "E-TRANSFER JANE DOE", debit: 0, credit: 50,
            transactionType: .income, accountID: UUID()
        )
        _ = vm.linkReimbursement(expense: tx, toIncome: income)
        return tx
    }

    @Test func revertKeepsLockedType() throws {
        let dir = TempDataDirectory()
        try seedCategories(dir)
        let vm = makeVM(dir: dir)
        let tx = lockedRetypedExpense(vm)
        #expect(vm.isTypeLocked(tx))
        #expect(vm.revertClassification(for: tx))
        let stored = try #require(try persistedEdit(dir, tx.contentHash))
        #expect(stored.transactionType == .expense)
        #expect(stored.category == nil)
    }

    @Test func updateClassificationKeepsLockedType() throws {
        let dir = TempDataDirectory()
        try seedCategories(dir)
        let vm = makeVM(dir: dir)
        let tx = lockedRetypedExpense(vm)
        #expect(vm.updateClassification(for: tx, type: .income, category: nil, subcategory: nil))
        let stored = try #require(try persistedEdit(dir, tx.contentHash))
        #expect(stored.transactionType == .expense)
    }
}
