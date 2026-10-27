import SwiftUI

private struct SavingsRateCell {
    let year: Int
    let month: Int
    let rate: Double?
}

struct SavingsRateHeatmap: View {
    let data: [MonthlyMetric]

    @State private var hoveredCell: (year: Int, month: Int)?

    private let monthLetters = ["J","F","M","A","M","J","J","A","S","O","N","D"]
    private let cellSize: CGFloat = 40
    private let cellGap: CGFloat = 4
    private let yearLabelWidth: CGFloat = 44

    private var grid: [[SavingsRateCell]] {
        let calendar = Calendar.current
        var byYearMonth: [Int: [Int: Double?]] = [:]
        for metric in data {
            let comps = calendar.dateComponents([.year, .month], from: metric.month)
            guard let year = comps.year, let month = comps.month else { continue }
            byYearMonth[year, default: [:]][month] = metric.savingsRate
        }
        return byYearMonth.keys.sorted().map { year in
            (1...12).map { month in
                SavingsRateCell(year: year, month: month, rate: byYearMonth[year]?[month] ?? nil)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: cellGap) {
            headerRow
            ForEach(Array(grid.enumerated()).reversed(), id: \.offset) { _, row in
                yearRow(row)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: cellGap) {
            Color.clear.frame(width: yearLabelWidth)
            ForEach(Array(monthLetters.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: cellSize)
            }
        }
    }

    private func yearRow(_ row: [SavingsRateCell]) -> some View {
        HStack(spacing: cellGap) {
            Text(row.first.map { String($0.year) } ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: yearLabelWidth, alignment: .trailing)
            ForEach(row, id: \.month) { cell in
                cellView(cell)
            }
        }
    }

    private func cellView(_ cell: SavingsRateCell) -> some View {
        let isHovered = hoveredCell.map { $0.year == cell.year && $0.month == cell.month } ?? false

        return RoundedRectangle(cornerRadius: 6)
            .fill(cellColor(for: cell.rate))
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if isHovered {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.25))
                        if let rate = cell.rate {
                            Text("\(Int((rate * 100).rounded()))%")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .onHover { active in
                hoveredCell = active ? (cell.year, cell.month) : nil
            }
    }

    private func cellColor(for rate: Double?) -> Color {
        Color.savingsRate(rate)
    }
}
