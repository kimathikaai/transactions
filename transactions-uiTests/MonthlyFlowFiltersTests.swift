import Foundation
import Testing
@testable import transactions_ui

@Suite("Monthly flow filters — netReimbursements")
struct MonthlyFlowFiltersTests {

    // MARK: - Helpers

    private func month(_ year: Int, _ m: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: m, day: 15))!
    }

    private func metric(_ year: Int, _ m: Int, income: Double, expense: Double) -> MonthlyMetric {
        MonthlyMetric(
            month: Calendar.current.dateInterval(of: .month, for: month(year, m))!.start,
            income: income,
            expense: expense,
            net: income - expense,
            savingsRate: income > 0 ? (income - expense) / income : nil,
            expenseByCategory: [:],
            incomeByCategory: [:],
            balances: [UUID(): 123],
            savingsRateEMA6: 0.42,
            savingsRateEMA6Unclamped: 0.42,
            incomeMoMDelta: 10,
            expenseMoMDelta: 20,
            netMoMDelta: 30
        )
    }

    private func tx(_ hash: String, _ year: Int, _ m: Int, _ type: TransactionType) -> Transaction {
        Transaction(
            contentHash: hash,
            date: month(year, m),
            details: hash,
            debit: type == .expense ? 100 : 0,
            credit: type == .income ? 100 : 0,
            transactionType: type,
            accountID: UUID()
        )
    }

    // MARK: - Tests

    @Test("No links returns the metrics unchanged")
    func noLinksUnchanged() {
        let metrics = [metric(2025, 1, income: 4000, expense: 3000)]
        let result = netReimbursements(from: metrics, transactions: [], links: [:])
        #expect(result.count == 1)
        #expect(result[0].income == 4000)
        #expect(result[0].expense == 3000)
        #expect(result[0].net == 1000)
    }

    @Test("Same-month link nets both income and expense in that month")
    func sameMonthNetsBothSides() {
        let metrics = [metric(2025, 1, income: 4000, expense: 3000)]
        let transactions = [
            tx("exp1", 2025, 1, .expense),
            tx("inc1", 2025, 1, .income),
        ]
        let links = ["exp1": ReimbursementLink(reimbursementHash: "inc1", amount: 300)]
        let result = netReimbursements(from: metrics, transactions: transactions, links: links)
        #expect(result[0].income == 3700)
        #expect(result[0].expense == 2700)
        #expect(result[0].net == 1000)
    }

    @Test("Cross-month link nets each side in its own month")
    func crossMonthNetsPerMonth() {
        let metrics = [
            metric(2025, 1, income: 4000, expense: 3000),
            metric(2025, 2, income: 5000, expense: 2000),
        ]
        // Expense lives in January; its reimbursement income lands in February.
        let transactions = [
            tx("exp1", 2025, 1, .expense),
            tx("inc1", 2025, 2, .income),
        ]
        let links = ["exp1": ReimbursementLink(reimbursementHash: "inc1", amount: 500)]
        let result = netReimbursements(from: metrics, transactions: transactions, links: links)
        // January: only the expense side drops.
        #expect(result[0].income == 4000)
        #expect(result[0].expense == 2500)
        // February: only the income side drops.
        #expect(result[1].income == 4500)
        #expect(result[1].expense == 2000)
    }

    @Test("Dangling source still nets the expense side")
    func danglingSourceNetsExpenseOnly() {
        let metrics = [metric(2025, 1, income: 4000, expense: 3000)]
        // Only the expense resolves; the source income hash is unknown.
        let transactions = [tx("exp1", 2025, 1, .expense)]
        let links = ["exp1": ReimbursementLink(reimbursementHash: "gone", amount: 300)]
        let result = netReimbursements(from: metrics, transactions: transactions, links: links)
        #expect(result[0].income == 4000)
        #expect(result[0].expense == 2700)
    }

    @Test("Dangling expense still nets the income side")
    func danglingExpenseNetsIncomeOnly() {
        let metrics = [metric(2025, 1, income: 4000, expense: 3000)]
        let transactions = [tx("inc1", 2025, 1, .income)]
        let links = ["gone": ReimbursementLink(reimbursementHash: "inc1", amount: 300)]
        let result = netReimbursements(from: metrics, transactions: transactions, links: links)
        #expect(result[0].income == 3700)
        #expect(result[0].expense == 3000)
    }

    @Test("Offsets are clamped so income and expense never go negative")
    func clampsAtZero() {
        let metrics = [metric(2025, 1, income: 100, expense: 200)]
        let transactions = [
            tx("exp1", 2025, 1, .expense),
            tx("inc1", 2025, 1, .income),
        ]
        // Amount exceeds both the month's income and expense.
        let links = ["exp1": ReimbursementLink(reimbursementHash: "inc1", amount: 5000)]
        let result = netReimbursements(from: metrics, transactions: transactions, links: links)
        #expect(result[0].income == 0)
        #expect(result[0].expense == 0)
        #expect(result[0].net == 0)
    }

    @Test("Net and savings rate are recomputed from the netted figures")
    func recomputesNetAndSavingsRate() {
        let metrics = [metric(2025, 1, income: 4000, expense: 3000)]
        let transactions = [
            tx("exp1", 2025, 1, .expense),
            tx("inc1", 2025, 1, .income),
        ]
        let links = ["exp1": ReimbursementLink(reimbursementHash: "inc1", amount: 1000)]
        let result = netReimbursements(from: metrics, transactions: transactions, links: links)
        // income 3000, expense 2000 -> net 1000, rate 1000/3000.
        #expect(result[0].net == 1000)
        #expect(result[0].savingsRate == 1000.0 / 3000.0)
    }

    @Test("Non-flow fields are carried through untouched")
    func carriesThroughUnrelatedFields() {
        let metrics = [metric(2025, 1, income: 4000, expense: 3000)]
        let transactions = [
            tx("exp1", 2025, 1, .expense),
            tx("inc1", 2025, 1, .income),
        ]
        let links = ["exp1": ReimbursementLink(reimbursementHash: "inc1", amount: 300)]
        let result = netReimbursements(from: metrics, transactions: transactions, links: links)
        #expect(result[0].balances == metrics[0].balances)
        #expect(result[0].netWorth == metrics[0].netWorth)
        #expect(result[0].savingsRateEMA6 == 0.42)
        #expect(result[0].incomeMoMDelta == 10)
        #expect(result[0].expenseMoMDelta == 20)
        #expect(result[0].netMoMDelta == 30)
    }
}
