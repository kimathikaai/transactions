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
        case .net: .primary
        }
    }

    func value(from flow: MonthlyMetric) -> Double {
        switch self {
        case .income: flow.income
        case .expenses: flow.expense
        case .net: flow.net
        }
    }
}

struct MonthlyFlowBarChart: View {
    @Environment(AppViewModel.self) private var vm
    let data: [MonthlyMetric]

    var body: some View {
        let displayedMonth = vm.displayedMonth ?? .now

        Chart {
            ForEach(data) { flow in
                BarMark(
                    x: .value("Month", flow.month),
                    y: .value("Income", flow.income),
                    width: 20
                )
                .foregroundStyle(by: .value("Type", FlowCategory.income))
                .opacity(flow.month == displayedMonth ? 1.0 : 0.25)

                BarMark(
                    x: .value("Month", flow.month),
                    y: .value("Expense", -flow.expense),
                    width: 20
                )
                .foregroundStyle(by: .value("Type", FlowCategory.expenses))
                .opacity(flow.month == displayedMonth ? 1.0 : 0.25)
            }

            ForEach(data) { flow in
                LineMark(
                    x: .value("Month", flow.month),
                    y: .value("Net", flow.net)
                )
                .foregroundStyle(by: .value("Type", FlowCategory.net))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .symbol {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 6, height: 6)
                }
                .interpolationMethod(.catmullRom)
            }

            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.gray.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks { _ in }
        }
        .chartXAxis {
            AxisMarks { _ in }
        }
        .chartForegroundStyleScale(
            domain: FlowCategory.allCases,
            range: FlowCategory.allCases.map(\.color)
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
