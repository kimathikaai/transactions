import Foundation
import Testing
@testable import transactions_ui

@Suite("Category breakdown")
struct CategoryBreakdownTests {

    // MARK: - Helpers

    private func snapshot(
        amount: Double,
        type: TransactionType = .expense,
        category: CategoryID? = nil
    ) -> TransactionSnapshot {
        let tx = Transaction(
            contentHash: UUID().uuidString,
            date: Date(timeIntervalSince1970: 0),
            details: "row",
            debit: amount < 0 ? -amount : 0,
            credit: amount > 0 ? amount : 0,
            transactionType: type,
            category: category,
            accountID: UUID()
        )
        return TransactionSnapshot(
            transaction: tx,
            id: tx.id,
            date: tx.date,
            accountID: tx.accountID,
            accountName: "Chequing",
            details: tx.details,
            effectiveType: type,
            effectiveCategory: category,
            effectiveSubcategory: nil,
            effectiveAmount: amount,
            notes: nil,
            isEdited: false,
            isReimbursed: false,
            isUsed: false
        )
    }

    private let food = CategoryID(rawValue: "cat_food")
    private let transport = CategoryID(rawValue: "cat_transport")

    // MARK: - Tests

    @Test("Groups by root category and sorts descending by amount")
    func groupsAndSortsDescending() {
        let result = CategoryBreakdownCard.breakdown(from: [
            snapshot(amount: -20, category: food),
            snapshot(amount: -90, category: transport),
            snapshot(amount: -30, category: food),
        ], type: .expense)

        #expect(result.total == 140)
        #expect(result.slices.map(\.id) == [transport, food])
        #expect(result.slices[0].amount == 90)
        #expect(result.slices[1].amount == 50)
    }

    @Test("Uncategorized expenses land in the uncategorized bucket")
    func nilCategoryBecomesUncategorized() {
        let result = CategoryBreakdownCard.breakdown(from: [
            snapshot(amount: -25, category: nil),
        ], type: .expense)

        #expect(result.slices.count == 1)
        #expect(result.slices[0].id == .uncategorized)
        #expect(result.slices[0].amount == 25)
    }

    @Test("Expense breakdown ignores income and transfers")
    func expenseIgnoresOtherTypes() {
        let result = CategoryBreakdownCard.breakdown(from: [
            snapshot(amount: -40, type: .expense, category: food),
            snapshot(amount: 5000, type: .income, category: food),
            snapshot(amount: 300, type: .transfer_in, category: food),
            snapshot(amount: -300, type: .transfer_out, category: food),
        ], type: .expense)

        #expect(result.total == 40)
        #expect(result.slices.count == 1)
        #expect(result.slices[0].amount == 40)
    }

    @Test("Income breakdown keeps income and drops expenses and transfers")
    func incomeIgnoresOtherTypes() {
        let result = CategoryBreakdownCard.breakdown(from: [
            snapshot(amount: 5000, type: .income, category: food),
            snapshot(amount: 1200, type: .income, category: transport),
            snapshot(amount: -40, type: .expense, category: food),
            snapshot(amount: 300, type: .transfer_in, category: food),
            snapshot(amount: -300, type: .transfer_out, category: food),
        ], type: .income)

        #expect(result.total == 6200)
        #expect(result.slices.map(\.id) == [food, transport])
        #expect(result.slices[0].amount == 5000)
        #expect(result.slices[1].amount == 1200)
    }

    @Test("Shares sum to one and amounts use absolute value")
    func sharesSumToOne() {
        let result = CategoryBreakdownCard.breakdown(from: [
            snapshot(amount: -10, category: food),
            snapshot(amount: -30, category: transport),
            snapshot(amount: -60, category: nil),
        ], type: .expense)

        let sum = result.slices.reduce(0) { $0 + $1.share }
        #expect(abs(sum - 1) < 0.0001)
        #expect(result.slices.allSatisfy { $0.amount > 0 })
        #expect(result.slices[0].share == 0.6)
    }

    @Test("Empty and type-free input yields no slices")
    func emptyInputYieldsNothing() {
        #expect(CategoryBreakdownCard.breakdown(from: [], type: .expense).slices.isEmpty)
        #expect(CategoryBreakdownCard.breakdown(from: [], type: .expense).total == 0)

        let incomeOnly = CategoryBreakdownCard.breakdown(from: [
            snapshot(amount: 1000, type: .income, category: food),
        ], type: .expense)
        #expect(incomeOnly.slices.isEmpty)
        #expect(incomeOnly.total == 0)
    }

    @Test("Column-major chunking splits ranked slices into fixed-row columns")
    func columnMajorChunking() {
        let slices = (0..<14).map {
            CategoryBreakdownCard.CategorySlice(
                id: CategoryID(rawValue: "c\($0)"), amount: Double(14 - $0), share: 0)
        }
        let cols = CategoryBreakdownCard.columnChunks(slices, rowsPerColumn: 3)

        #expect(cols.map(\.count) == [3, 3, 3, 3, 2])              // 14 → 3 / 3 / 3 / 3 / 2
        #expect(cols[0].first?.id == CategoryID(rawValue: "c0"))   // rank 1 tops column 1
        #expect(cols[1].first?.id == CategoryID(rawValue: "c3"))   // column 2 continues rank
        #expect(CategoryBreakdownCard.columnChunks([], rowsPerColumn: 3).isEmpty)
    }
}
