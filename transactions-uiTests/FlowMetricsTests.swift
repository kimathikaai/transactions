import Foundation
import Testing
@testable import transactions_ui

@Suite("Flow metrics (filtered range chart feed)")
struct FlowMetricsTests {

    // MARK: - Helpers

    private func month(_ year: Int, _ m: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: m, day: 1))!
    }

    /// A snapshot dated on the first of `(year, m)`. `amount` is the signed effective
    /// amount (positive income, negative expense — mirroring `CategoryBreakdownTests`).
    private func snapshot(_ year: Int, _ m: Int, amount: Double, type: TransactionType) -> TransactionSnapshot {
        let date = month(year, m)
        let tx = Transaction(
            contentHash: UUID().uuidString,
            date: date,
            details: "row",
            debit: amount < 0 ? -amount : 0,
            credit: amount > 0 ? amount : 0,
            transactionType: type,
            category: nil,
            accountID: UUID()
        )
        return TransactionSnapshot(
            transaction: tx,
            id: tx.id,
            date: date,
            accountID: tx.accountID,
            accountName: "Chequing",
            details: tx.details,
            effectiveType: type,
            effectiveCategory: nil,
            effectiveSubcategory: nil,
            effectiveAmount: amount,
            notes: nil,
            isEdited: false,
            isReimbursed: false,
            isUsed: false
        )
    }

    // MARK: - Tests

    @Test("Bins income/expense/net into the right months")
    func binsPerMonth() {
        let metrics = AppViewModel.flowMetrics(
            from: [
                snapshot(2025, 1, amount: 4000, type: .income),
                snapshot(2025, 1, amount: -1500, type: .expense),
                snapshot(2025, 2, amount: 5000, type: .income),
                snapshot(2025, 2, amount: -2000, type: .expense),
            ],
            start: month(2025, 1), end: month(2025, 2)
        )

        #expect(metrics.count == 2)
        #expect(metrics[0].month == month(2025, 1))
        #expect(metrics[0].income == 4000)
        #expect(metrics[0].expense == 1500)
        #expect(metrics[0].net == 2500)
        #expect(metrics[1].income == 5000)
        #expect(metrics[1].expense == 2000)
        #expect(metrics[1].net == 3000)
    }

    @Test("Emits a zero metric for months in range with no matching snapshot")
    func zeroFillsEmptyMonths() {
        let metrics = AppViewModel.flowMetrics(
            from: [snapshot(2025, 1, amount: 1000, type: .income)],
            start: month(2025, 1), end: month(2025, 3)
        )

        #expect(metrics.count == 3)
        #expect(metrics[1].month == month(2025, 2))
        #expect(metrics[1].income == 0)
        #expect(metrics[1].expense == 0)
        #expect(metrics[1].net == 0)
        #expect(metrics[2].month == month(2025, 3))
        #expect(metrics[2].income == 0)
    }

    @Test("Spans the full requested range even when snapshots cluster in a sub-range")
    func spansFullRange() {
        let metrics = AppViewModel.flowMetrics(
            from: [snapshot(2025, 6, amount: -300, type: .expense)],
            start: month(2025, 1), end: month(2025, 12)
        )

        #expect(metrics.count == 12)
        #expect(metrics.first?.month == month(2025, 1))
        #expect(metrics.last?.month == month(2025, 12))
        #expect(metrics[5].month == month(2025, 6))
        #expect(metrics[5].expense == 300)
    }

    @Test("Ignores non-income/expense types (transfers)")
    func ignoresTransfers() {
        let metrics = AppViewModel.flowMetrics(
            from: [
                snapshot(2025, 1, amount: 800, type: .transfer_in),
                snapshot(2025, 1, amount: -800, type: .transfer_out),
                snapshot(2025, 1, amount: 200, type: .income),
            ],
            start: month(2025, 1), end: month(2025, 1)
        )

        #expect(metrics.count == 1)
        #expect(metrics[0].income == 200)
        #expect(metrics[0].expense == 0)
        #expect(metrics[0].net == 200)
    }

    @Test("Empty input still spans the range with all-zero metrics")
    func emptyInputZeroRange() {
        let metrics = AppViewModel.flowMetrics(
            from: [], start: month(2025, 1), end: month(2025, 2)
        )

        #expect(metrics.count == 2)
        #expect(metrics.allSatisfy { $0.income == 0 && $0.expense == 0 && $0.net == 0 })
    }
}
