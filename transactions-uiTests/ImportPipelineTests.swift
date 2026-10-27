import Foundation
import Testing
@testable import transactions_ui

struct ImportPipelineTests {

    private func date(_ s: String) -> Date {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: s)!
    }

    private func makeAccount(name: String = "Test") -> Account {
        Account(name: name, type: .chequing, initialBalance: 0, csvFileName: "")
    }

    // Reusable fixture with two expense leaves, one transfer_in root, one
    // transfer_out root. No other categories — unmatched rows should surface
    // as (nil, nil).
    private func fixture() -> [transactions_ui.Category] {
        [
            transactions_ui.Category(id: "cat_food", displayName: "Food", parent: nil,
                     color: "#8dd3c7", symbol: "fork.knife",
                     transactionType: .expense, patterns: []),
            transactions_ui.Category(id: "cat_cafe", displayName: "Cafe", parent: "cat_food",
                     color: "#8dd3c7", symbol: "cup.and.saucer.fill",
                     transactionType: .expense, patterns: ["STARBUCKS"]),
            transactions_ui.Category(id: "cat_dining", displayName: "Dining", parent: "cat_food",
                     color: "#8dd3c7", symbol: "fork.knife",
                     transactionType: .expense, patterns: ["STAR"]),
            transactions_ui.Category(id: "cat_tin", displayName: "Transfer In", parent: nil,
                     color: "#aec6cf", symbol: "arrow.down.circle.fill",
                     transactionType: .transfer_in, patterns: []),
            transactions_ui.Category(id: "cat_tout", displayName: "Transfer Out", parent: nil,
                     color: "#aec6cf", symbol: "arrow.up.circle.fill",
                     transactionType: .transfer_out, patterns: []),
        ]
    }

    @Test("Debit becomes expense with negative amount")
    func debitIsExpense() throws {
        let acct = makeAccount()
        let rows = [BankRow(date: date("2025-01-10"), details: "STARBUCKS", debit: 5.50, credit: 0)]
        let txs = ImportPipeline.makeTransactions(from: rows, accountID: acct.id, transferKeywords: [], categories: [])
        #expect(txs.count == 1)
        #expect(txs[0].transactionType == .expense)
        #expect(txs[0].amount == -5.50)
    }

    @Test("Credit becomes income with positive amount")
    func creditIsIncome() throws {
        let acct = makeAccount()
        let rows = [BankRow(date: date("2025-01-12"), details: "PAYROLL", debit: 0, credit: 2000.00)]
        let txs = ImportPipeline.makeTransactions(from: rows, accountID: acct.id, transferKeywords: [], categories: [])
        #expect(txs[0].transactionType == .income)
        #expect(txs[0].amount == 2000.00)
    }

    @Test("Transfer keyword reclassifies to transfer_in/out by sign, resolving cat ids from catalog")
    func transferReclassification() throws {
        let acct = makeAccount()
        let cats = fixture()
        let rows = [
            BankRow(date: date("2025-01-05"), details: "INTERNET TRANSFER TO SAVINGS", debit: 500, credit: 0),
            BankRow(date: date("2025-01-06"), details: "INTERNET TRANSFER FROM SAVINGS", debit: 0, credit: 500),
        ]
        let txs = ImportPipeline.makeTransactions(from: rows, accountID: acct.id,
                                                  transferKeywords: ["INTERNET TRANSFER"], categories: cats)
        #expect(txs.map(\.transactionType) == [.transfer_out, .transfer_in])
        #expect(txs[0].category?.rawValue == "cat_tout")
        #expect(txs[1].category?.rawValue == "cat_tin")
    }

    @Test("First matching leaf wins (source order across catalog)")
    func firstMatchWins() throws {
        let acct = makeAccount()
        let cats = fixture()
        let rows = [BankRow(date: date("2025-01-10"), details: "STARBUCKS", debit: 5.00, credit: 0)]
        let txs = ImportPipeline.makeTransactions(from: rows, accountID: acct.id, transferKeywords: [], categories: cats)
        #expect(txs[0].category?.rawValue == "cat_food")
        #expect(txs[0].subcategory?.rawValue == "cat_cafe")
    }

    @Test("Unmatched non-transfer rows yield nil category/subcategory")
    func unmatchedIsNil() throws {
        let acct = makeAccount()
        let rows = [BankRow(date: date("2025-01-10"), details: "MYSTERY MERCHANT", debit: 1.00, credit: 0)]
        let txs = ImportPipeline.makeTransactions(from: rows, accountID: acct.id, transferKeywords: [], categories: fixture())
        #expect(txs[0].category == nil)
        #expect(txs[0].subcategory == nil)
    }

    @Test("Transfer with missing transfer root falls back to nil category")
    func transferMissingRoot() throws {
        let acct = makeAccount()
        let rows = [BankRow(date: date("2025-01-05"), details: "INTERNET TRANSFER TO SAVINGS", debit: 500, credit: 0)]
        let txs = ImportPipeline.makeTransactions(from: rows, accountID: acct.id,
                                                  transferKeywords: ["INTERNET TRANSFER"], categories: [])
        #expect(txs[0].transactionType == .transfer_out)
        #expect(txs[0].category == nil)
    }
}
