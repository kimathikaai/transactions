import Foundation

/// Presentation filters for the monthly Flow chart. These are pure transforms
/// over an already-computed `[MonthlyMetric]` array — they never touch the
/// load/mutation recompute path in `AppViewModel`.

/// Returns a copy of `metrics` with reimbursement amounts netted out of the
/// flow: for each link, `link.amount` is subtracted from **expense** in the
/// reimbursed expense's month and from **income** in the source income's month
/// (the two can differ). Income and expense are clamped at zero; `net` and
/// `savingsRate` are recomputed from the netted figures. All other fields
/// (`balances`/net worth, savings-rate EMA, month-over-month deltas) are carried
/// through untouched — netting is a flow-presentation filter, not a change to
/// real account balances.
///
/// A link contributes an offset only for the side whose transaction resolves in
/// `transactions`; a dangling side is simply skipped.
func netReimbursements(
    from metrics: [MonthlyMetric],
    transactions: [Transaction],
    links: [String: ReimbursementLink]
) -> [MonthlyMetric] {
    guard !links.isEmpty else { return metrics }

    let calendar = Calendar.current
    let monthByHash: [String: Date] = Dictionary(
        transactions.map { ($0.contentHash, calendar.dateInterval(of: .month, for: $0.date)!.start) },
        uniquingKeysWith: { first, _ in first }
    )

    var incomeOffset: [Date: Double] = [:]
    var expenseOffset: [Date: Double] = [:]
    for (expenseHash, link) in links {
        if let expenseMonth = monthByHash[expenseHash] {
            expenseOffset[expenseMonth, default: 0] += link.amount
        }
        if let incomeMonth = monthByHash[link.reimbursementHash] {
            incomeOffset[incomeMonth, default: 0] += link.amount
        }
    }

    return metrics.map { metric in
        let income = max(0, metric.income - (incomeOffset[metric.month] ?? 0))
        let expense = max(0, metric.expense - (expenseOffset[metric.month] ?? 0))
        let net = income - expense
        return MonthlyMetric(
            month: metric.month,
            income: income,
            expense: expense,
            net: net,
            savingsRate: income > 0 ? net / income : nil,
            expenseByCategory: metric.expenseByCategory,
            incomeByCategory: metric.incomeByCategory,
            balances: metric.balances,
            savingsRateEMA6: metric.savingsRateEMA6,
            savingsRateEMA6Unclamped: metric.savingsRateEMA6Unclamped,
            incomeMoMDelta: metric.incomeMoMDelta,
            expenseMoMDelta: metric.expenseMoMDelta,
            netMoMDelta: metric.netMoMDelta
        )
    }
}
