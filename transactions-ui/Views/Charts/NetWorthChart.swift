import Charts
import SwiftUI

/// Every month's net worth as a plain line, flush to both edges, with a zero rule as the
/// only axis. The tooltip sits over the plot's top-left corner. Tapping pins the hovered
/// month; while pinned, any tap unpins.
struct NetWorthChart: View {
    @Environment(AppViewModel.self) private var vm
    let data: [MonthlyMetric]

    @State private var hoverSelection: Date?

    private func snapshot(for month: Date) -> MonthlyMetric? {
        data.first { $0.month == month }
    }

    private func monthOverMonthChange(for month: Date) -> Double? {
        guard let index = data.firstIndex(where: { $0.month == month }), index > 0 else { return nil }
        return data[index].netWorth - data[index - 1].netWorth
    }

    /// First to last month with no padding, so the latest month sits on the right edge.
    /// Nil with fewer than two months (a zero-width domain), leaving the scale automatic.
    private var xDomain: ClosedRange<Date>? {
        guard let first = data.first?.month, let last = data.last?.month, first < last else { return nil }
        return first...last
    }

    /// Always includes zero so the zero rule is visible as the axis.
    private var yDomain: ClosedRange<Double> {
        guard let minVal = data.map(\.netWorth).min(),
              let maxVal = data.map(\.netWorth).max() else {
            return 0...1
        }
        let floor = min(0, minVal - 0.05 * abs(minVal))
        let ceiling = max(0, maxVal + 0.05 * abs(maxVal))
        return floor < ceiling ? floor...ceiling : floor...(floor + 1)
    }

    var body: some View {
        withXDomain(chart)
            .chartXSelection(value: $hoverSelection)
            .onChange(of: hoverSelection) { _, newValue in
                vm.publishHover(newValue)
            }
            .onTapGesture(perform: handleTap)
            .overlay(alignment: .topLeading) {
                if let month = vm.displayedMonth {
                    tooltipView(for: month)
                        .allowsHitTesting(false)
                }
            }
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.gray.opacity(0.3))

            if let month = vm.displayedMonth {
                if vm.pinnedMonth != nil {
                    cursorRule(at: month)
                        .annotation(position: .overlay, alignment: .top, spacing: 0) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                } else {
                    cursorRule(at: month)
                }
            }

            ForEach(data) { snapshot in
                // Fills down to the zero rule (AreaMark's default baseline).
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
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Month", snapshot.month),
                    y: .value("Net Worth", snapshot.netWorth)
                )
                .foregroundStyle(.teal)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }

            if let month = vm.displayedMonth, let snap = snapshot(for: month) {
                PointMark(
                    x: .value("Month", month),
                    y: .value("Net Worth", snap.netWorth)
                )
                .foregroundStyle(.teal)
                .symbolSize(30)
            }
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
    }

    private func cursorRule(at month: Date) -> some ChartContent {
        RuleMark(x: .value("Selected", month))
            .foregroundStyle(Color.gray.opacity(0.3))
            .lineStyle(StrokeStyle(lineWidth: 2))
    }

    @ViewBuilder
    private func withXDomain(_ chart: some View) -> some View {
        if let xDomain {
            chart.chartXScale(domain: xDomain)
        } else {
            chart
        }
    }

    /// Unlike the shared `togglePin`, a tap while pinned always unpins, wherever it lands.
    private func handleTap() {
        if vm.pinnedMonth != nil {
            vm.pinnedMonth = nil
        } else if let month = vm.hoveredMonth {
            vm.togglePin(month)
        }
    }

    /// One interpolated Text, not an HStack of Image + Text: that HStack measured the
    /// monospaced-digit amount narrower than it drew, truncating it to "$3,8…".
    private func changeText(_ change: Double) -> some View {
        let arrow = Text(Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right"))
            .font(.system(size: 8))
        return Text("\(arrow)\(abs(change), format: .cadWhole)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(change >= 0 ? Color.income : Color.expense)
    }

    private func tooltipView(for month: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(month, format: .dateTime.year().month(.abbreviated))
                    .font(.caption.bold())
                if vm.pinnedMonth != nil {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let snap = snapshot(for: month) {
                HStack(spacing: 4) {
                    Text(snap.netWorth, format: .cadWhole)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.teal)
                    if let change = monthOverMonthChange(for: month) {
                        changeText(change)
                    }
                }
            }
        }
    }
}
