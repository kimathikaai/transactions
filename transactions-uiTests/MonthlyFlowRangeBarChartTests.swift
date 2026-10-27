import Foundation
import Testing
@testable import transactions_ui

@Suite("Monthly flow range bar chart")
struct MonthlyFlowRangeBarChartTests {

    // MARK: - Helpers

    private func month(_ year: Int, _ m: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: m, day: 1))!
    }

    private func metric(_ year: Int, _ m: Int, income: Double, expense: Double) -> MonthlyMetric {
        MonthlyMetric(
            month: month(year, m),
            income: income,
            expense: expense,
            net: income - expense,
            savingsRate: nil,
            expenseByCategory: [:],
            incomeByCategory: [:],
            balances: [:],
            savingsRateEMA6: nil,
            savingsRateEMA6Unclamped: nil,
            incomeMoMDelta: nil,
            expenseMoMDelta: nil,
            netMoMDelta: nil
        )
    }

    // MARK: - resolveRange

    @Test("Plain click selects a single month")
    func plainClickSingleMonth() {
        let r = MonthlyFlowRangeBarChart.resolveRange(
            anchor: month(2025, 6), tapped: month(2025, 6), extend: false,
            globalStart: month(2024, 1), globalEnd: month(2026, 1)
        )
        #expect(r.start == month(2025, 6))
        #expect(r.end == month(2025, 6))
    }

    @Test("Shift-extend forward yields the inclusive ordered range")
    func extendForward() {
        let r = MonthlyFlowRangeBarChart.resolveRange(
            anchor: month(2025, 1), tapped: month(2025, 3), extend: true,
            globalStart: month(2024, 1), globalEnd: month(2026, 1)
        )
        #expect(r.start == month(2025, 1))
        #expect(r.end == month(2025, 3))
    }

    @Test("Shift-extend backward yields the same ordered range (order-independent)")
    func extendBackward() {
        let r = MonthlyFlowRangeBarChart.resolveRange(
            anchor: month(2025, 3), tapped: month(2025, 1), extend: true,
            globalStart: month(2024, 1), globalEnd: month(2026, 1)
        )
        #expect(r.start == month(2025, 1))
        #expect(r.end == month(2025, 3))
    }

    @Test("Endpoints clamp to the global bounds")
    func clampsToGlobalBounds() {
        let r = MonthlyFlowRangeBarChart.resolveRange(
            anchor: month(2023, 1), tapped: month(2027, 1), extend: true,
            globalStart: month(2024, 1), globalEnd: month(2026, 1)
        )
        #expect(r.start == month(2024, 1))
        #expect(r.end == month(2026, 1))
    }

    @Test("Result invariant: start is never after end")
    func invariantStartLessThanOrEqualEnd() {
        let r = MonthlyFlowRangeBarChart.resolveRange(
            anchor: month(2025, 5), tapped: month(2025, 2), extend: true,
            globalStart: month(2024, 1), globalEnd: month(2026, 1)
        )
        #expect(r.start <= r.end)
    }

    // MARK: - summary

    @Test("Multi-month range sums income/expense/net and averages by count")
    func multiMonthSumsAndAverages() {
        let metrics = [
            metric(2025, 1, income: 4000, expense: 3000),
            metric(2025, 2, income: 5000, expense: 2000),
            metric(2025, 3, income: 6000, expense: 4000),
        ]
        let s = MonthlyFlowRangeBarChart.summary(
            metrics: metrics, start: month(2025, 1), end: month(2025, 3)
        )
        #expect(s.count == 3)
        #expect(s.income == 15000)
        #expect(s.expense == 9000)
        #expect(s.net == 6000)
        #expect(s.incomeAvg == 5000)
        #expect(s.expenseAvg == 3000)
        #expect(s.netAvg == 2000)
        #expect(s.showsAverages == true)
    }

    @Test("Single-month range hides averages and sums that month only")
    func singleMonthNoAverages() {
        let metrics = [
            metric(2025, 1, income: 4000, expense: 3000),
            metric(2025, 2, income: 5000, expense: 2000),
        ]
        let s = MonthlyFlowRangeBarChart.summary(
            metrics: metrics, start: month(2025, 2), end: month(2025, 2)
        )
        #expect(s.count == 1)
        #expect(s.income == 5000)
        #expect(s.expense == 2000)
        #expect(s.net == 3000)
        #expect(s.showsAverages == false)
    }

    @Test("Range endpoints are inclusive on both ends")
    func inclusiveEndpoints() {
        let metrics = [
            metric(2025, 1, income: 1000, expense: 0),
            metric(2025, 2, income: 1000, expense: 0),
            metric(2025, 3, income: 1000, expense: 0),
        ]
        let s = MonthlyFlowRangeBarChart.summary(
            metrics: metrics, start: month(2025, 1), end: month(2025, 3)
        )
        #expect(s.count == 3)
        #expect(s.income == 3000)
    }

    @Test("Empty selection yields zeros and no averages")
    func emptySelection() {
        let s = MonthlyFlowRangeBarChart.summary(
            metrics: [], start: month(2025, 1), end: month(2025, 3)
        )
        #expect(s.count == 0)
        #expect(s.income == 0)
        #expect(s.expense == 0)
        #expect(s.net == 0)
        #expect(s.showsAverages == false)
    }
}
