import Charts
import SwiftUI

/// A vertical, 120pt-wide variant of `MonthlyFlowRangeBarChart`: the same income/expense
/// month-range control rotated 90°. Months run down the Y axis (newest at the top), bars grow
/// horizontally from the zero rule (income right, expenses left), and the range summary sits
/// underneath. It scrolls vertically, showing `visibleMonths` at a time.
///
/// Not wired into the app yet — exercised via its `#Preview` only. Deliberately a standalone
/// copy (no shared types with the horizontal chart), so its private helpers mirror that file.
///
/// Selection mechanics are identical to the horizontal chart: plain click selects one month
/// (the anchor); plain-clicking the sole selection resets to the full range; shift+click
/// (macOS) extends from the anchor. The row under the pointer is resolved via
/// `.chartYSelection` on the integer month-index axis, and hovering brightens it. There is no
/// hover date pill or guide line.
///
/// Precondition: `globalStart <= startMonth <= endMonth <= globalEnd`, and the global range
/// spans at least two months.
struct MonthlyFlowRangeVerticalBarChart: View {
    @Binding var startMonth: Date
    @Binding var endMonth: Date

    let globalStart: Date
    let globalEnd: Date
    let metrics: [MonthlyMetric]

    /// The shift-select anchor. Kept separately from the committed range because it may be
    /// the *later* month of the range (shift-extend backward).
    @State private var anchorMonth: Date = .now

    /// The raw y-value under the pointer on the integer month-index axis, published by
    /// `.chartYSelection`. `nil` when not hovering. Snapped to a whole index by `snappedIndex`.
    @State private var selectedIndex: Double?

    /// The month the cursor is currently over. Drives the hover highlight only.
    private var hoveredMonth: Date? { snappedIndex(selectedIndex).map { metrics[$0].month } }

    /// The `startMonth` value this view last committed itself, so an external range change
    /// (Reset button, data reload) can be told apart from our own commit.
    @State private var lastCommittedStart: Date?

    /// Bottom edge of the scrollable window, as a month index. Seeded so the most recent
    /// `visibleMonths` are in view (newest at the top).
    @State private var scrollPosition: Double = 0

    /// How many months are visible at once before you scroll.
    private let visibleMonths = 16

    private let rowHeight: CGFloat = 20
    private let width: CGFloat = 140

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            chart
            Divider()
            RangeSummaryPanel(
                summary: Self.summary(metrics: metrics, start: startMonth, end: endMonth),
                start: startMonth,
                end: endMonth
            )
        }
        .frame(width: width)
        .onAppear {
            anchorMonth = startMonth
            lastCommittedStart = startMonth
            seedScroll()
        }
        // Re-seed the anchor only when the range is reset externally; our own commits set
        // `lastCommittedStart` first, so a shift-extend never moves the anchor.
        .onChange(of: startMonth) { _, newValue in
            if newValue != lastCommittedStart { anchorMonth = newValue }
        }
        // Metrics load asynchronously; re-seed to the newest window once the count is known.
        .onChange(of: metrics.count) { seedScroll() }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            barMarks
            netLine
            RuleMark(x: .value("Zero", 0))
                .foregroundStyle(Color.gray.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartForegroundStyleScale(
            domain: FlowCategory.allCases,
            range: FlowCategory.allCases.map(\.color)
        )
        .chartYAxis { AxisMarks { _ in } }
        .chartXAxis { AxisMarks { _ in } }
        // Higher index (newer month) plots higher, so newest is at the top. One index of
        // padding each side.
        .chartYScale(domain: -1.0 ... Double(metrics.count))
        .chartXScale(domain: xDomain)
        .chartScrollableAxes(.vertical)
        .chartYVisibleDomain(length: Double(visibleMonths))
        .chartScrollPosition(y: $scrollPosition)
        .chartLegend(.hidden)
        .frame(height: CGFloat(visibleMonths) * rowHeight)
        // Same approach as the horizontal chart: `.chartYSelection` + a plain tap gesture,
        // neither of which swallows the scroll drag.
        .chartYSelection(value: $selectedIndex)
        .onTapGesture { handleTap(snappedIndex(selectedIndex).map(month(at:))) }
    }

    /// Explicit `xStart`/`xEnd` spans from zero: with both axes numeric, a plain
    /// `BarMark(x:y:)` is drawn as a vertical column, not a horizontal bar.
    @ChartContentBuilder
    private var barMarks: some ChartContent {
        ForEach(Array(metrics.enumerated()), id: \.offset) { index, flow in
            BarMark(
                xStart: .value("Zero", 0),
                xEnd: .value("Income", flow.income),
                y: .value("Month", Double(index)),
                height: 12
            )
            .foregroundStyle(by: .value("Type", FlowCategory.income))
            .opacity(barOpacity(flow.month))

            BarMark(
                xStart: .value("Zero", 0),
                xEnd: .value("Expense", -flow.expense),
                y: .value("Month", Double(index)),
                height: 12
            )
            .foregroundStyle(by: .value("Type", FlowCategory.expenses))
            .opacity(barOpacity(flow.month))
        }
    }

    @ChartContentBuilder
    private var netLine: some ChartContent {
        ForEach(Array(metrics.enumerated()), id: \.offset) { index, flow in
            LineMark(
                x: .value("Net", flow.net),
                y: .value("Month", Double(index))
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
    }

    private func isSelected(_ month: Date) -> Bool {
        month >= startMonth && month <= endMonth
    }

    /// X-axis domain fitted to the full dataset's extent (every month, not just the scroll
    /// window), so the axis stays fixed while scrolling.
    private var xDomain: ClosedRange<Double> {
        guard !metrics.isEmpty else { return -1 ... 1 }

        let right = metrics.map { max($0.income, $0.net) }.max() ?? 0
        let left = metrics.map { min(-$0.expense, $0.net) }.min() ?? 0

        // Pad ~8% so bars and net dots don't kiss the plot edges; guard the all-zero case.
        let pad = max((right - left) * 0.08, 1)
        return (left - pad) ... (right + pad)
    }

    /// Rows in the committed range are full opacity; the hovered row also brightens as a
    /// preview of what a click will select; everything else is dimmed.
    private func barOpacity(_ month: Date) -> Double {
        isSelected(month) || month == hoveredMonth ? 1.0 : 0.25
    }

    // MARK: - Selection ↔ bindings

    /// Resolve a tap into the month bindings. A plain click selects a single month and moves
    /// the anchor there; a shift+click (macOS only) extends the range from the anchor.
    /// `nil` (a click landing on no row) is a no-op.
    private func handleTap(_ raw: Date?) {
        guard let raw else { return }
        let tapped = monthStart(raw)

        var extend = false
        #if os(macOS)
        extend = NSEvent.modifierFlags.contains(.shift)
        #endif

        // Plain-click a row that is already the sole selection → toggle back to the full range.
        if !extend, startMonth == tapped, endMonth == tapped {
            anchorMonth = tapped
            lastCommittedStart = globalStart
            startMonth = globalStart
            endMonth = globalEnd
            return
        }

        let r = Self.resolveRange(
            anchor: extend ? anchorMonth : tapped,
            tapped: tapped,
            extend: extend,
            globalStart: globalStart,
            globalEnd: globalEnd
        )
        if !extend { anchorMonth = tapped }  // plain click resets anchor; shift never moves it
        lastCommittedStart = r.start          // mark this as our own change (see onChange above)
        startMonth = r.start
        endMonth = r.end
    }

    /// Position the scroll window on the most recent `visibleMonths` (the top of the chart).
    private func seedScroll() {
        scrollPosition = Double(max(0, metrics.count - visibleMonths))
    }

    // MARK: - Index ↔ month mapping

    /// Snap the raw continuous y from `.chartYSelection` to the nearest row index. Returns
    /// `nil` in the padding gutter (index out of range).
    private func snappedIndex(_ raw: Double?) -> Int? {
        guard let raw else { return nil }
        let i = Int(raw.rounded())   // nearest row center; plain Int(_:) truncates → biased
        return metrics.indices.contains(i) ? i : nil
    }

    private func month(at index: Int) -> Date { metrics[index].month }

    // MARK: - Date helpers

    private func monthStart(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    // MARK: - Pure logic (copied from MonthlyFlowRangeBarChart)

    /// Plain: a single month `(tapped, tapped)`. Extend: the ordered inclusive span of
    /// `anchor`/`tapped`. Both clamped to `globalStart...globalEnd`; never empty.
    private static func resolveRange(
        anchor: Date,
        tapped: Date,
        extend: Bool,
        globalStart: Date,
        globalEnd: Date
    ) -> (start: Date, end: Date) {
        func clamp(_ d: Date) -> Date { min(max(d, globalStart), globalEnd) }
        let a = clamp(anchor)
        let t = clamp(tapped)
        guard extend else { return (t, t) }
        return (min(a, t), max(a, t))
    }

    /// Sum income/expense/net over months in `start...end` inclusive, with per-month
    /// averages (zero when nothing matches).
    private static func summary(metrics: [MonthlyMetric], start: Date, end: Date) -> VerticalFlowSummary {
        let matched = metrics.filter { $0.month >= start && $0.month <= end }
        let income = matched.reduce(0) { $0 + $1.income }
        let expense = matched.reduce(0) { $0 + $1.expense }
        let net = matched.reduce(0) { $0 + $1.net }
        let count = matched.count
        let divisor = Double(max(count, 1))
        return VerticalFlowSummary(
            income: income,
            expense: expense,
            net: net,
            count: count,
            incomeAvg: income / divisor,
            expenseAvg: expense / divisor,
            netAvg: net / divisor
        )
    }
}

/// Summed and averaged flow figures over a selected month range. A private copy of
/// `FlowSummary` (which is internal to the horizontal chart's file).
private struct VerticalFlowSummary {
    let income: Double
    let expense: Double
    let net: Double
    let count: Int
    let incomeAvg: Double
    let expenseAvg: Double
    let netAvg: Double

    /// Averages are only meaningful (and shown) for multi-month ranges.
    var showsAverages: Bool { count > 1 }
}

// MARK: - Summary panel

/// Bottom readout of the selected range, sized for the 120pt column: a header naming the
/// selection (wraps for ranges) plus summed Inc / Exp / Net rows. Hovering (macOS) swaps the
/// figures to per-month averages for multi-month ranges.
private struct RangeSummaryPanel: View {
    let summary: VerticalFlowSummary
    let start: Date
    let end: Date

    @State private var isHovering = false

    /// Only swap to averages for multi-month ranges — for a single month avg == total.
    private var showingAverages: Bool { isHovering && summary.showsAverages }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(headerText)
                .font(.caption.bold())
                .fixedSize(horizontal: false, vertical: true)   // let a range wrap to two lines

            Divider()

            row(.income, summary.income, avg: summary.incomeAvg)
            row(.expenses, summary.expense, avg: summary.expenseAvg)
            row(.net, summary.net, avg: summary.netAvg)
        }
        .padding(.horizontal, 10)
        .padding(.top,16)
        .padding(.bottom,4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())          // hover registers over the padding, not just text
        .onHover { isHovering = $0 }
    }

    /// "March 2026" for a single month; "Jan 2026 – Mar 2026" for a range.
    private var headerText: String {
        if summary.count <= 1 {
            return start.formatted(.dateTime.month(.wide).year())
        }
        let a = start.formatted(.dateTime.month(.abbreviated).year())
        let b = end.formatted(.dateTime.month(.abbreviated).year())
        return "\(a) – \(b)"
    }

    private func row(_ category: FlowCategory, _ sum: Double, avg: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(category.color).frame(width: 6, height: 6)
            Text(category.shortLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Group {
                if showingAverages {
                    Text("\(avg.formatted(.cadWhole)) /mo")
                } else {
                    Text(sum, format: .cadWhole)
                }
            }
            .font(.caption2.monospacedDigit())
            .lineLimit(1)
            .contentTransition(.numericText())
        }
    }
}

// MARK: - Flow category

/// Income / Expenses / Net styling. A file-private copy of the enum in
/// `MonthlyFlowRangeBarChart.swift`, plus short labels for the narrow panel.
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

    var shortLabel: String {
        switch self {
        case .income: "Inc"
        case .expenses: "Exp"
        case .net: "Net"
        }
    }
}

// MARK: - Previews

private func month(_ year: Int, _ month: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
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

#Preview("Vertical") {
    @Previewable @State var from = month(2025, 12)
    @Previewable @State var to = month(2026, 3)

    let metrics = (0..<27).map { i -> MonthlyMetric in
        let base = month(2024, 1)
        let d = Calendar.current.date(byAdding: .month, value: i, to: base)!
        let y = Calendar.current.component(.year, from: d)
        let mo = Calendar.current.component(.month, from: d)
        return metric(y, mo, income: 4000 + Double((i * 137) % 1500),
                      expense: 2500 + Double((i * 211) % 1800))
    }

    SectionContainer(title: "Month Range") {
        MonthlyFlowRangeVerticalBarChart(
            startMonth: $from,
            endMonth: $to,
            globalStart: month(2024, 1),
            globalEnd: month(2026, 3),
            metrics: metrics
        )
    }
    .padding(24)
    .fixedSize()
}
