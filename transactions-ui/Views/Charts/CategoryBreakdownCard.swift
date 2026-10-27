import SwiftUI

/// One proportional bar of a single transaction type's mix (expenses or income)
/// across the selected month range, grouped by root category, plus a three-column
/// legend.
///
/// The caller passes already-filtered snapshots, so the card mirrors exactly the transactions
/// rendered below it — every filter on the transactions page is reflected here.
struct CategoryBreakdownCard: View {
    @Environment(AppViewModel.self) private var vm

    /// One category's slice of the range total.
    struct CategorySlice: Identifiable {
        let id: CategoryID
        let amount: Double
        /// Fraction of the range total, 0...1.
        let share: Double
    }

    /// Which transaction type this card breaks down — `.expense` or `.income`.
    private let type: TransactionType
    private let slices: [CategorySlice]
    private let total: Double
    private let startMonth: Date
    private let endMonth: Date
    /// Reports the tapped category to the parent, which owns toggle/reset of the page filter.
    private let onSelectCategory: (CategoryID) -> Void

    /// Category currently hovered (via bar segment or legend row); drives the linked
    /// cross-highlight — greys the matching legend row and dims the other bar segments.
    @State private var hoveredCategory: CategoryID? = nil

    private let barHeight: CGFloat = 22
    private let segmentSpacing: CGFloat = 1
    /// Floor so a sub-1% category still leaves a visible mark.
    private let minSegmentWidth: CGFloat = 2

    private let legendRowsPerColumn = 3
    private let amountRailWidth: CGFloat = 52   // fits "$6,620"; trailing-aligned
    private let percentRailWidth: CGFloat = 30  // fits "100%";  trailing-aligned
    private let legendRowSpacing: CGFloat = 3
    private let legendRowHeight: CGFloat = 18    // fixed so a 3-row column has an exact height
    private let legendColumnWidth: CGFloat = 200 // fixed width → ~3 columns visible, rest scroll
    private let legendScrollBarGutter: CGFloat = 14 // reserved strip so the scroll bar sits below the rows

    /// Constant legend height: exactly `legendRowsPerColumn` rows tall regardless of how many
    /// categories are present, so the card never changes height as filters change the count.
    private var legendViewportHeight: CGFloat {
        CGFloat(legendRowsPerColumn) * legendRowHeight
            + CGFloat(legendRowsPerColumn - 1) * legendRowSpacing
    }

    init(snapshots: [TransactionSnapshot], type: TransactionType, startMonth: Date, endMonth: Date,
         onSelectCategory: @escaping (CategoryID) -> Void) {
        let aggregate = Self.breakdown(from: snapshots, type: type)
        self.type = type
        self.slices = aggregate.slices
        self.total = aggregate.total
        self.startMonth = startMonth
        self.endMonth = endMonth
        self.onSelectCategory = onSelectCategory
    }

    // MARK: - Aggregation

    /// Groups the given transaction `type` by root category, descending by amount. All
    /// other types (the opposite flow and both transfer directions) are dropped, matching
    /// `AppViewModel.computeMonthlyMetrics`.
    static func breakdown(from snapshots: [TransactionSnapshot], type: TransactionType) -> (slices: [CategorySlice], total: Double) {
        var amountByCategory: [CategoryID: Double] = [:]
        var total: Double = 0

        for snap in snapshots where snap.effectiveType == type {
            let amount = abs(snap.effectiveAmount)
            amountByCategory[snap.effectiveCategory ?? .uncategorized, default: 0] += amount
            total += amount
        }

        guard total > 0 else { return ([], 0) }

        let slices = amountByCategory
            .sorted { $0.value > $1.value }
            .map { CategorySlice(id: $0.key, amount: $0.value, share: $0.value / total) }

        return (slices, total)
    }

    /// Splits the ranked slices column-major into columns of `rowsPerColumn` rows each (the
    /// last column may be short), so reading down each column follows descending rank and
    /// the column count grows with the slice count. For 14 slices at 3 rows this yields
    /// chunks of 3 / 3 / 3 / 3 / 2 (5 columns).
    static func columnChunks(_ slices: [CategorySlice], rowsPerColumn: Int) -> [[CategorySlice]] {
        guard !slices.isEmpty, rowsPerColumn > 0 else { return [] }
        return stride(from: 0, to: slices.count, by: rowsPerColumn).map {
            Array(slices[$0 ..< min($0 + rowsPerColumn, slices.count)])
        }
    }

    // MARK: - Body

    var body: some View {
        if total > 0 {
            // Card chrome (background/glass/padding) is supplied by the enclosing
            // SectionContainer.
            VStack(alignment: .leading, spacing: 10) {
//                header
                bar
                legend
            }
        } else {
            Text("No \(noun) in this range")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Lowercased noun for the type, used in the empty-state copy.
    private var noun: String {
        type == .income ? "income" : "expenses"
    }

    /// Headline tint for the type, matching the finance color tokens.
    private var tint: Color {
        type == .income ? .income : .expense
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(startMonth, format: .monthYear)
            Text("–")
                .foregroundStyle(.secondary)
            Text(endMonth, format: .monthYear)
            Spacer(minLength: 8)
            Text(total, format: .cadWhole)
                .foregroundStyle(tint)
        }
        .font(.system(size: 11, weight: .semibold))
        .monospacedDigit()
    }

    // MARK: - Bar

    private var bar: some View {
        GeometryReader { geo in
            HStack(spacing: segmentSpacing) {
                ForEach(slices) { slice in
                    Rectangle()
                        .fill(color(for: slice.id))
                        .frame(width: width(for: slice, in: geo.size.width))
                        .opacity(hoveredCategory == nil || hoveredCategory == slice.id ? 1 : 0.35)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredCategory = hovering ? slice.id : nil
                            }
                        }
                        .onTapGesture { onSelectCategory(slice.id) }
                        .pointerStyle(.link)
                }
            }
        }
        .frame(height: barHeight)
        .clipShape(.rect(cornerRadius: 5))
        .accessibilityLabel("\(type == .income ? "Income" : "Expense") breakdown by category")
    }

    /// Reserves `minSegmentWidth` per slice plus the inter-segment spacing, then hands the
    /// remainder out by share — so the row never overflows its clip and drops the tail.
    private func width(for slice: CategorySlice, in totalWidth: CGFloat) -> CGFloat {
        let count = CGFloat(slices.count)
        let reserved = count * minSegmentWidth + max(0, count - 1) * segmentSpacing
        let distributable = max(0, totalWidth - reserved)
        return minSegmentWidth + slice.share * distributable
    }

    // MARK: - Legend

    private var legend: some View {
        // Fixed-height viewport (exactly `legendRowsPerColumn` rows tall) so the card never
        // changes height as filters change the category count. Extra columns overflow to the
        // right and are reached by horizontal scrolling; the indicator stays visible on overflow.
        // The bottom padding on the content itself reserves a strip so the horizontal scroll bar
        // sits below the rows instead of overlaying the last one (SwiftUI overlays it by default,
        // and short content is vertically centered — so an empty strip must live inside the content).
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                let cols = Self.columnChunks(slices, rowsPerColumn: legendRowsPerColumn)
                ForEach(Array(cols.enumerated()), id: \.offset) { index, column in
                    if index > 0 { Divider() }
                    legendColumn(column)
                }
            }
            .padding(.bottom, legendScrollBarGutter)
        }
        .frame(height: legendViewportHeight + legendScrollBarGutter)
        .scrollIndicators(.visible)
        .font(.caption2)
    }

    private func legendColumn(_ column: [CategorySlice]) -> some View {
        VStack(alignment: .leading, spacing: legendRowSpacing) {
            ForEach(column) { slice in legendRow(slice) }
        }
        .frame(width: legendColumnWidth, alignment: .leading)
    }

    private func legendRow(_ slice: CategorySlice) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol(for: slice.id))
                .foregroundStyle(color(for: slice.id))   // colored SF Symbol = the key
            Text(name(for: slice.id))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(slice.amount, format: .cadWhole)
                .monospacedDigit()
                .frame(width: amountRailWidth, alignment: .trailing)
            Text("\(Int((slice.share * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: percentRailWidth, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(height: legendRowHeight)   // fixed so the 3-row viewport height is exact
        // Legend text (name, amount, percent) is grey until this row is hovered — directly or
        // via the linked bar segment — then brightens to full strength. The symbol keeps its
        // own category color (its explicit foregroundStyle overrides this default).
        .foregroundStyle(hoveredCategory == slice.id ? .primary : .secondary)
        .contentShape(Rectangle())
        // Shared hover state (not `.hoverHighlight()`, whose internal state can't cross-link
        // to the bar). Mirrors HoverHighlight's Color.primary.opacity(0.07) look.
        .background(
            Color.primary.opacity(hoveredCategory == slice.id ? 0.07 : 0),
            in: RoundedRectangle(cornerRadius: 4)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredCategory = hovering ? slice.id : nil
            }
        }
        .onTapGesture { onSelectCategory(slice.id) }
        .pointerStyle(.link)
    }

    // MARK: - Category lookup

    private func color(for id: CategoryID) -> Color {
        if id == .uncategorized { return Color(hex: "#d9d9d9") }
        guard let def = vm.category(id: id) else { return .gray }
        return Color(hex: def.color)
    }

    private func symbol(for id: CategoryID) -> String {
        vm.category(id: id)?.symbol ?? "questionmark.circle.fill"
    }

    private func name(for id: CategoryID) -> String {
        if id == .uncategorized { return "Uncategorized" }
        return vm.category(id: id)?.displayName ?? id.rawValue    }
}

// MARK: - Preview

/// `(id, displayName, hex, SF Symbol, amount)`. The first six drive the "Typical" preview;
/// all fourteen drive "Long tail", whose last entries are deliberately sub-1% of the total.
private let previewFixtures: [(String, String, String, String, Double)] = [
    ("cat_food", "Food & Dining", "#EB5757", "fork.knife", 1_240),
    ("cat_transport", "Transportation", "#2D9CDB", "car.fill", 890),
    ("cat_housing", "Housing", "#F2994A", "house.fill", 610),
    ("cat_utilities", "Utilities", "#BB6BD9", "bolt.fill", 412),
    ("cat_groceries", "Groceries", "#27AE60", "cart.fill", 305),
    ("cat_health", "Health & Wellness", "#EB5757", "heart.fill", 190),
    ("cat_subscriptions", "Subscriptions & Memberships", "#56CCF2", "repeat.circle.fill", 96),
    ("cat_travel", "Travel", "#F2C94C", "airplane", 74),
    ("cat_shopping", "Shopping", "#9B51E0", "bag.fill", 58),
    ("cat_pets", "Pets", "#6FCF97", "pawprint.fill", 41),
    ("cat_gifts", "Gifts & Donations", "#EB8C57", "gift.fill", 22),
    ("cat_education", "Education", "#4F7FEA", "book.fill", 14),
    ("cat_fees", "Bank Fees", "#828282", "building.columns.fill", 6),
    ("cat_parking", "Parking", "#5B8C7B", "parkingsign.circle.fill", 3),
]

/// A view model whose six stores all point at a throwaway temp directory, pre-seeded with
/// `categories`. Passing `categoryStore:`/`csvDirectory:` explicitly matters: their defaults
/// resolve through `DataPaths` to the real source-tree `Data/` folder, so omitting them (as
/// the older previews in this project do) would read — and risk writing — live project data.
private func previewViewModel(categories: [Category]) -> AppViewModel {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    let categoryStore = CategoryStore(fileURL: dir.appendingPathComponent("categories.json"))
    // Written before the VM is built so the VM's own load() picks the catalog up.
    try? categoryStore.replaceAll(categories)
    return AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json")),
        categoryStore: categoryStore,
        csvDirectory: dir.appendingPathComponent("csv")
    )
}

private func previewSnapshot(amount: Double, categoryID: String) -> TransactionSnapshot {
    let category = CategoryID(rawValue: categoryID)
    let tx = Transaction(
        contentHash: "preview-\(categoryID)",
        date: Date(timeIntervalSince1970: 1_738_368_000),
        details: "Preview row",
        debit: amount,
        credit: 0,
        transactionType: .expense,
        category: category,
        accountID: UUID()
    )
    return TransactionSnapshot(
        transaction: tx,
        id: tx.id,
        date: tx.date,
        accountID: tx.accountID,
        accountName: "Chequing",
        details: tx.details,
        effectiveType: .expense,
        effectiveCategory: category,
        effectiveSubcategory: nil,
        effectiveAmount: -amount,
        notes: nil,
        isEdited: false,
        isReimbursed: false,
        isUsed: false
    )
}

/// Renders the card exactly as `TransactionsPage` does — 650pt wide, so legend column widths
/// and name truncation in the canvas match production.
private func previewCard(fixtureCount: Int) -> some View {
    let fixtures = Array(previewFixtures.prefix(fixtureCount))
    let vm = previewViewModel(categories: fixtures.map { id, name, color, symbol, _ in
        Category(
            id: id,
            displayName: name,
            parent: nil,
            color: color,
            symbol: symbol,
            transactionType: .expense,
            patterns: []
        )
    })

    return SectionContainer(title: "Spending") {
        CategoryBreakdownCard(
            snapshots: fixtures.map { id, _, _, _, amount in
                previewSnapshot(amount: amount, categoryID: id)
            },
            type: .expense,
            startMonth: Date(timeIntervalSince1970: 1_735_689_600),  // Jan 2025
            endMonth: Date(timeIntervalSince1970: 1_743_465_600),    // Apr 2025
            onSelectCategory: { _ in }
        )
    }
    .frame(width: 650)
    .padding(20)
    .environment(vm)
}

#Preview("Typical") {
    previewCard(fixtureCount: 6)
}

#Preview("Long tail") {
    previewCard(fixtureCount: previewFixtures.count)
}
