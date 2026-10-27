import Charts
import SwiftUI

struct MonthlySavingsRateBarChart: View {
    @Environment(AppViewModel.self) private var vm
    let data: [MonthlyMetric]

    var body: some View {
        let displayedMonth = vm.displayedMonth ?? .now

        Chart {
            ForEach(data) { flow in
                if let rate = clampedRate(for: flow) {
                    BarMark(
                        x: .value("Month", flow.month),
                        y: .value("Rate", rate),
                        width: 15
                    )
                    .foregroundStyle(Color.savingsRateAmount(rate))
                    .opacity(flow.month == displayedMonth ? 1.0 : 0.25)
                }
            }

            ForEach(data) { flow in
                if let ema = flow.savingsRateEMA6 {
                    LineMark(
                        x: .value("Month", flow.month),
                        y: .value("EMA", ema)
                    )
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks { _ in } }
        .chartXAxis { AxisMarks { _ in } }
        .syncMonthlyAxis()
        .monthlyTooltip(width: 170) { month in
            tooltipView(for: month)
        }
    }

    private func clampedRate(for flow: MonthlyMetric) -> Double? {
        flow.savingsRate.map { max(0, $0) }
    }

    private func percentLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func tooltipView(for month: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(month, format: .dateTime.year().month(.abbreviated))
                .font(.caption.bold())

            if let flow = data.first(where: { $0.month == month }) {
                Divider()

                HStack {
                    Circle()
                        .fill(Color.savingsRateAmount(clampedRate(for: flow)))
                        .frame(width: 6, height: 6)
                    Text("Savings Rate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(percentLabel(clampedRate(for: flow)))
                        .font(.caption2.monospacedDigit())
                }

                HStack {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 6, height: 6)
                    Text("6-mo EMA")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(percentLabel(flow.savingsRateEMA6))
                        .font(.caption2.monospacedDigit())
                }
            }
        }
        .padding(8)
    }
}
