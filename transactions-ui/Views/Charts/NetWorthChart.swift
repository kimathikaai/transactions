import Charts
import SwiftUI

struct NetWorthChart: View {
    @Environment(AppViewModel.self) private var vm
    let data: [MonthlyMetric]

    private func snapshot(for month: Date) -> MonthlyMetric? {
        data.first { $0.month == month }
    }

    private func monthOverMonthChange(for month: Date) -> Double? {
        guard let index = data.firstIndex(where: { $0.month == month }), index > 0 else { return nil }
        return data[index].netWorth - data[index - 1].netWorth
    }

    private var yDomain: ClosedRange<Double> {
        guard let minVal = data.map(\.netWorth).min(),
              let maxVal = data.map(\.netWorth).max() else {
            return 0...0
        }
        let floor = minVal - 0.05 * abs(minVal)
        let ceiling = maxVal + 0.05 * abs(maxVal)
        return floor...ceiling
    }

    var body: some View {
        let displayedMonth = vm.displayedMonth ?? .now

        Chart {
            ForEach(data) { snapshot in
                AreaMark(
                    x: .value("Month", snapshot.month),
                    y: .value("Net Worth", snapshot.netWorth)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.teal.opacity(0.6), .teal.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Month", snapshot.month),
                    y: .value("Net Worth", snapshot.netWorth)
                )
                .foregroundStyle(.teal)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            if let last = data.last {
                PointMark(
                    x: .value("Month", last.month),
                    y: .value("Net Worth", last.netWorth)
                )
                .foregroundStyle(.teal)
                .symbolSize(30)
            }

            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.gray.opacity(0.3))
                .zIndex(-1)

            RuleMark(x: .value("Selected", displayedMonth))
                .foregroundStyle(Color.gray.opacity(0.3))
                .zIndex(-1)
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks { _ in }
        }
        .chartXAxis {
            AxisMarks { _ in }
        }
        .chartYScale(domain: yDomain)
        .frame(maxHeight: .infinity)
        .syncMonthlyAxis()
        .monthlyTooltip(width: 170) { month in
            tooltipView(for: month)
        }
    }

    private func tooltipView(for month: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(month, format: .dateTime.year().month(.abbreviated))
                .font(.caption.bold())

            if let snap = snapshot(for: month) {
                HStack(spacing: 4) {
                    Text(snap.netWorth, format: .cadWhole)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.teal)
                    if let change = monthOverMonthChange(for: month) {
                        HStack(spacing: 1) {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 8))
                            Text(abs(change), format: .cadWhole)
                                .font(.caption2.monospacedDigit())
                        }
                        .foregroundStyle(change >= 0 ? Color.income : Color.expense)
                    }
                }

                Divider()
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(vm.accounts) { account in
                            if let balance = snap.balances[account.id] {
                                HStack {
                                    Text(account.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(balance, format: .cadWhole)
                                        .font(.caption2.monospacedDigit())
                                }
                            }
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.viewAligned)

            }
        }
        .padding(8)
    }
}
