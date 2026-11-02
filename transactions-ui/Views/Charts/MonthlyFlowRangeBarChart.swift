import Charts
import SwiftUI

/// A monthly income/expense bar chart that doubles as the month-range control for the
/// Transactions page. It scrolls horizontally, showing `visibleMonths` at a time.
///
/// Selection mechanics (deliberately simple):
///   • Plain click a bar → selects just that month; it becomes the *anchor*.
///   • Plain click the bar that is *already* the sole selection → resets to the full range.
///   • Shift+click another bar → selects the inclusive range between the anchor and the
///     clicked month (order-independent). Shift+click never moves the anchor, only sets
///     the far end.
///   • A plain click always resets to a new single-month anchor.
///   • There is always at least one month selected (never empty; no toggle-off).
///
/// Selection is committed by a **click**. The month under the pointer is resolved via
/// `.chartXSelection` (the same mechanism as `MonthlyTooltipOverlay`), which reports the
/// correct month even while the chart is scrolled. Crucially we do *not* lay a hit-testing
/// `.chartOverlay` rectangle over the plot — that captures the drag `.chartScrollableAxes`
/// needs and blocks scrolling; `.chartXSelection` + a plain `.onTapGesture` do not. Swift
/// Charts does not surface modifier keys, so on macOS we read `NSEvent.modifierFlags`
/// synchronously in the click handler (shift is still held on mouse-up) to tell a
/// shift+click from a plain click. On iOS/visionOS there is no shift key, so a tap always
/// selects a single month. Hovering a bar (macOS) previews it at full opacity via the same
/// `.chartXSelection` value, without committing.
///
/// Precondition (matches the caller in `TransactionListView.periodContent`): `globalStart
/// <= startMonth <= endMonth <= globalEnd`, and the global range spans at least two months.
struct MonthlyFlowRangeBarChart: View {
    @Binding var startMonth: Date
    @Binding var endMonth: Date

    let globalStart: Date
    let globalEnd: Date
    let metrics: [MonthlyMetric]

    /// The shift-select anchor. Persisted separately from the committed range because the
    /// anchor may be the *later* month of the range (shift-extend backward), so it can't be
    /// inferred from `startMonth`.
    @State private var anchorMonth: Date = .now

    /// The raw x-value under the pointer (a continuous position on the integer month-index
    /// axis), published by `.chartXSelection` — updated on macOS hover and on tap. `nil` when
    /// not hovering. Snapped to a whole index by `snappedIndex`.
    @State private var selectedIndex: Double?

    /// The month the cursor is currently over, snapped from `selectedIndex`. Drives the
    /// hover highlight only; `nil` when not hovering. iOS/visionOS never hover.
    private var hoveredMonth: Date? { snappedIndex(selectedIndex).map { metrics[$0].month } }

    /// The bar index the cursor is currently over, snapped from `selectedIndex`. Anchors the
    /// hover date label + guide line to the correct bar (even while scrolled); `nil` when not
    /// hovering.
    private var hoveredIndex: Int? { snappedIndex(selectedIndex) }

    /// The `startMonth` value this view last committed itself. Used to tell an external range
    /// change (Reset button, data reload) apart from our own commit, so re-seeding the anchor
    /// doesn't clobber it mid shift-extend (a backward extend legitimately moves `startMonth`).
    @State private var lastCommittedStart: Date?

    /// Left edge of the scrollable window, as a month index. Seeded to show the most recent
    /// `visibleMonths`.
    @State private var scrollPosition: Double = 0

    /// How many months are visible at once before you scroll.
    private let visibleMonths = 16

    private let chartHeight: CGFloat = 96
    private let panelWidth: CGFloat = 170

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            chart
            Divider()
            RangeSummaryPanel(
                summary: Self.summary(metrics: metrics, start: startMonth, end: endMonth),
                start: startMonth,
                end: endMonth
            )
            .frame(width: panelWidth)
        }
        .onAppear {
            anchorMonth = startMonth
            lastCommittedStart = startMonth
            seedScroll()
        }
        // Re-seed the anchor only when the range is reset *externally* (Reset button, data
        // reload re-running setDefaultDateRange). Our own commits set `lastCommittedStart`
        // first, so they're skipped here — a shift-extend never moves the anchor.
        .onChange(of: startMonth) { _, newValue in
            if newValue != lastCommittedStart { anchorMonth = newValue }
        }
        // Metrics load asynchronously, so the initial `.onAppear` seed can run while `metrics`
        // is still empty (scrolling to the leftmost index 0). Re-seed to the rightmost window
        // once the month count is known or changes. Filter changes recompute values without
        // changing the count, so this never fights a manual scroll during normal use.
        .onChange(of: metrics.count) { seedScroll() }
        .fixedSize(horizontal: false, vertical: true)   // stop the Divider from stretching the row

    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            barMarks
            netLine
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.gray.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1))
            hoverGuide
        }
        .chartForegroundStyleScale(
            domain: FlowCategory.allCases,
            range: FlowCategory.allCases.map(\.color)
        )
        .chartYAxis { AxisMarks { _ in } }
        .chartXAxis { AxisMarks { _ in } }
        .chartXScale(domain: -1.0 ... Double(metrics.count))   // one index of padding each side
        .chartYScale(domain: yDomain)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: Double(visibleMonths))
        .chartScrollPosition(x: $scrollPosition)
        .chartLegend(.hidden)
        .frame(height: chartHeight)
        // Selection/hover via `.chartXSelection`, which reports the raw x on the integer
        // month-index axis (1 unit == 1 month, so it stays correct even while scrolled — no
        // drift, unlike the old average-month-in-seconds Date axis). `snappedIndex` rounds it
        // to the bar under the pointer; a plain `.onTapGesture` commits the click. Neither
        // intercepts the `.chartScrollableAxes` drag — unlike a hit-testing `.chartOverlay`
        // rectangle, which swallows scroll.
        .chartXSelection(value: $selectedIndex)
        .onTapGesture { handleTap(snappedIndex(selectedIndex).map(month(at:))) }
    }

    @ChartContentBuilder
    private var barMarks: some ChartContent {
        ForEach(Array(metrics.enumerated()), id: \.offset) { index, flow in
            BarMark(
                x: .value("Month", Double(index)),
                y: .value("Income", flow.income),
                width: 20
            )
            .foregroundStyle(by: .value("Type", FlowCategory.income))
            .opacity(barOpacity(flow.month))

            BarMark(
                x: .value("Month", Double(index)),
                y: .value("Expense", -flow.expense),
                width: 20
            )
            .foregroundStyle(by: .value("Type", FlowCategory.expenses))
            .opacity(barOpacity(flow.month))
        }
    }

    @ChartContentBuilder
    private var netLine: some ChartContent {
        ForEach(Array(metrics.enumerated()), id: \.offset) { index, flow in
            LineMark(
                x: .value("Month", Double(index)),
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
    }

    /// A faint dashed vertical guide at the hovered bar, footed by a "Jan 2026" pill that
    /// follows the cursor as you scrub. Rendered as a chart mark + annotation (not a
    /// hit-testing `.chartOverlay`) so it stays anchored while scrolled and never swallows the
    /// scroll drag. Only present while hovering (macOS pointer); absent on touch platforms.
    @ChartContentBuilder
    private var hoverGuide: some ChartContent {
        if let index = hoveredIndex {
            RuleMark(x: .value("Hover", Double(index)))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(
                    position: .bottom,
                    spacing: 4,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    Text(metrics[index].month, format: .dateTime.month(.abbreviated).year())
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.2)))
                        .fixedSize()
                }
        }
    }

    private func isSelected(_ month: Date) -> Bool {
        month >= startMonth && month <= endMonth
    }

    /// Y-axis domain fitted to the full dataset's extent (every month, not just the scroll
    /// window), so the axis stays fixed while scrolling.
    private var yDomain: ClosedRange<Double> {
        guard !metrics.isEmpty else { return -1 ... 1 }

        let top = metrics.map { max($0.income, $0.net) }.max() ?? 0
        let bottom = metrics.map { min(-$0.expense, $0.net) }.min() ?? 0

        // Pad ~8% so bars and net dots don't kiss the plot edges; guard the degenerate
        // all-zero case so the domain is never empty.
        let pad = max((top - bottom) * 0.08, 1)
        return (bottom - pad) ... (top + pad)
    }

    /// Bars in the committed range are full opacity; the hovered bar also brightens as a
    /// preview of what a click will select; everything else is dimmed.
    private func barOpacity(_ month: Date) -> Double {
        isSelected(month) || month == hoveredMonth ? 1.0 : 0.25
    }

    // MARK: - Selection ↔ bindings

    /// Resolve a tap into the month bindings. A plain click selects a single month and moves
    /// the anchor there; a shift+click (macOS only) extends the range from the anchor to the
    /// tapped month, leaving the anchor put. `nil` (a click landing on no bar) is a no-op.
    private func handleTap(_ raw: Date?) {
        guard let raw else { return }
        let tapped = monthStart(raw)

        var extend = false
        #if os(macOS)
        extend = NSEvent.modifierFlags.contains(.shift)
        #endif

        // Plain-click a bar that is already the sole selection → toggle back to the full range.
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

    /// Position the scroll window on the most recent `visibleMonths` so the default range is
    /// in view on load.
    private func seedScroll() {
        scrollPosition = Double(max(0, metrics.count - visibleMonths))
    }

    // MARK: - Index ↔ month mapping

    /// Snap the raw continuous x reported by `.chartXSelection` to the nearest bar index.
    /// Returns `nil` when the pointer is in the padding gutter (index out of range).
    private func snappedIndex(_ raw: Double?) -> Int? {
        guard let raw else { return nil }
        let i = Int(raw.rounded())   // nearest bar center; plain Int(_:) truncates → biased
        return metrics.indices.contains(i) ? i : nil
    }

    private func month(at index: Int) -> Date { metrics[index].month }

    // MARK: - Date helpers

    private func monthStart(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    // MARK: - Pure logic (unit-tested)

    /// Compute the committed month range from a tap. Plain (`extend == false`): a single
    /// month `(tapped, tapped)`. Extend: the ordered inclusive span of `anchor`/`tapped`.
    /// Both endpoints are clamped to `globalStart...globalEnd`, and the result always
    /// satisfies `start <= end` (never empty).
    static func resolveRange(
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

    /// Sum income/expense/net over the metrics whose month falls in `start...end` inclusive,
    /// with per-month averages. `count` is the number of matched months; averages are
    /// `sum / count` (zero when nothing matches).
    static func summary(metrics: [MonthlyMetric], start: Date, end: Date) -> FlowSummary {
        let matched = metrics.filter { $0.month >= start && $0.month <= end }
        let income = matched.reduce(0) { $0 + $1.income }
        let expense = matched.reduce(0) { $0 + $1.expense }
        let net = matched.reduce(0) { $0 + $1.net }
        let count = matched.count
        let divisor = Double(max(count, 1))
        return FlowSummary(
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

/// Summed and averaged flow figures over a selected month range.
struct FlowSummary {
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

/// Persistent right-side readout of the selected range: a header naming the selection plus
/// summed Income / Expenses / Net rows. Totals show by default; hovering the panel (macOS)
/// swaps the figures in place to per-month averages (`… /mo`) for multi-month ranges. Touch
/// platforms never fire `.onHover`, so they stay totals-only.
private struct RangeSummaryPanel: View {
    let summary: FlowSummary
    let start: Date
    let end: Date

    /// True while the pointer is over the panel (macOS only). Drives the totals→averages swap.
    @State private var isHovering = false

    /// Only swap to averages when hovering *and* the selection spans multiple months — for a
    /// single month avg == total, so a `/mo` suffix would be misleading.
    private var showingAverages: Bool { isHovering && summary.showsAverages }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerText)
                .font(.caption.bold())

            Divider()

            row(.income, summary.income, avg: summary.incomeAvg)
            row(.expenses, summary.expense, avg: summary.expenseAvg)
            row(.net, summary.net, avg: summary.netAvg)
        }
        .padding(8)
        .contentShape(Rectangle())          // hover registers over the padding, not just text
        .onHover { isHovering = $0 }
    }

    /// "March 2026" for a single month; "Jan 2026 – Mar 2026" for a range. Formatted inline
    /// via `.dateTime` — the shared `.monthYear` style is `MMM-YY` and there is no range style.
    private var headerText: String {
        if summary.count <= 1 {
            return start.formatted(.dateTime.month(.wide).year())
        }
        let a = start.formatted(.dateTime.month(.abbreviated).year())
        let b = end.formatted(.dateTime.month(.abbreviated).year())
        return "\(a) – \(b)"
    }

    private func row(_ category: FlowCategory, _ sum: Double, avg: Double) -> some View {
        HStack {
            Circle().fill(category.color).frame(width: 6, height: 6)
            Text(category.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Group {
                if showingAverages {
                    Text("\(avg.formatted(.cadWhole)) /mo")
                } else {
                    Text(sum, format: .cadWhole)
                }
            }
            .font(.caption2.monospacedDigit())
            .contentTransition(.numericText())
        }
    }
}

// MARK: - Flow category

/// Income / Expenses / Net styling. A file-private copy of the same enum in
/// `MonthlyFlowBarChart.swift` (that one is file-private and can't be shared); if a third
/// consumer appears, promote to a shared type.
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

#Preview("Multi-year") {
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
        MonthlyFlowRangeBarChart(
            startMonth: $from,
            endMonth: $to,
            globalStart: month(2024, 1),
            globalEnd: month(2026, 3),
            metrics: metrics
        )
    }
    .padding(24)
    .frame(width: 640)
}
