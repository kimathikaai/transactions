import Charts
import SwiftUI

private enum FlowCategory: String, CaseIterable, Plottable {
    case income = "Income"
    case expenses = "Expenses"
    case net = "Net"

    var color: Color {
        switch self {
        case .income: .income
        case .expenses: .expense
        case .net: .gray
        }
    }

    var dashed: Bool {
        self == .net
    }

    func value(from flow: MonthlyMetric) -> Double {
        switch self {
        case .income: flow.income
        case .expenses: flow.expense
        case .net: flow.net
        }
    }
}

private struct FlowSeries: Identifiable {
    let id: FlowCategory
    let values: [(month: Date, amount: Double)]

    var color: Color { id.color }
    var dashed: Bool { id.dashed }
}

struct MonthlyFlowChart: View {
    @Environment(AppViewModel.self) private var vm
    let data: [MonthlyMetric]

    private var series: [FlowSeries] {
        FlowCategory.allCases.map { category in
            FlowSeries(id: category, values: data.map { ($0.month, category.value(from: $0)) })
        }
    }

    var body: some View {
        let displayedMonth = vm.displayedMonth ?? .now

        Chart {
            ForEach(series) { s in
                ForEach(s.values, id: \.month) { point in
                    LineMark(
                        x: .value("Month", point.month),
                        y: .value("Amount", point.amount)
                    )
                    .foregroundStyle(by: .value("Type", s.id))
                    .interpolationMethod(.catmullRom)
                }
            }

            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.gray.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

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
        .chartForegroundStyleScale(
            domain: series.map(\.id),
            range: series.map(\.color)
        )
        .syncMonthlyAxis()
        .monthlyTooltip(width: 170) { month in
            tooltipView(for: month)
        }
    }

    private func tooltipView(for month: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(month, format: .dateTime.year().month(.abbreviated))
                .font(.caption.bold())

            if let flow = data.first(where: { $0.month == month }) {
                Divider()
                ForEach(FlowCategory.allCases, id: \.self) { category in
                    HStack {
                        Circle().fill(category.color).frame(width: 6, height: 6)
                        Text(category.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(category.value(from: flow), format: .cadWhole)
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .padding(8)
    }
}
