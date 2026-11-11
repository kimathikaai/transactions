import SwiftUI
import UniformTypeIdentifiers

/// The Transactions page: Expenses / Income breakdowns side by side on top, then the
/// transaction list with the vertical month range chart to its right. Income and Month Range
/// share one fixed-width right column; Expenses and the list take the rest. There are no
/// section-tab rails (and no rail gutter). A header toggle swaps the list card for the
/// Reimbursements review.
struct TransactionSplitView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var searchText = ""
    @State private var dateFrom: Date = .distantPast
    @State private var dateTo: Date = .now
    @State private var selectedAccount: Account? = nil
    @State private var selectedType: TransactionType? = nil
    @State private var selectedCategory: CategoryID? = nil
    @State private var selectedSubcategory: SubcategoryID? = nil
    @State private var initialized = false
    /// The transaction open in the one-stop modal, and which section to land on.
    @State private var detailRequest: TransactionDetailRequest?
    @State private var isExporterPresented = false
    @State private var exportDocument = TransactionsCSVDocument(csv: "")
    @State private var cachedTransactions: [TransactionSnapshot] = []
    /// Flow range chart's metrics — filtered by category/subcategory/account/search only
    /// (never date-range or type). Recomputed via `recomputeChartMetrics()`.
    @State private var cachedChartMetrics: [MonthlyMetric] = []
    @State private var sortField: SortField = .date
    @State private var sortAscending = false

    /// Shared width of the right-hand column (Income card above, Month Range card below):
    /// one 200pt breakdown legend column + the card's 2×20pt padding, so Income's first legend
    /// column is fully visible.
    private let sideColumnWidth: CGFloat = 240

    /// Months visible in the vertical range chart — sized so the page fits the 700pt window.
    private let visibleRangeMonths = 15

    /// Measured height of the Month Range card. The Transactions card is pinned to it so the
    /// two bottoms line up; `nil` until first layout (the list then takes the free height).
    @State private var monthRangeCardHeight: CGFloat?

    /// When true the list card shows `ReimbursementReviewView` instead of transactions.
    @State private var showingReimbursements = false

    /// Field the transaction list is ordered by. The default (`.date`, descending)
    /// reproduces the newest-first order inherited from `transactionsByDateDesc`.
    private enum SortField {
        case date, description, amount

        var title: String {
            switch self {
            case .date: "Date"
            case .description: "Description"
            case .amount: "Amount"
            }
        }

        /// Direction applied when this field is first selected.
        var defaultAscending: Bool {
            switch self {
            case .date: false        // newest first
            case .description: true  // A→Z
            case .amount: false      // largest magnitude first
            }
        }
    }

    private var hasActiveFilters: Bool {
        selectedAccount != nil
            || selectedType != nil
            || selectedCategory != nil
            || selectedSubcategory != nil
    }

    /// First day of the month after `dateTo`, used as exclusive upper bound for filtering.
    private var nextMonthAfterEnd: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: dateTo) ?? dateTo
    }

    /// Filters shared by the transaction list and the flow chart: account, category
    /// (+ subcategory), and search. The list layers date-range and type on top; the chart
    /// omits those by design (it spans every month and draws both income + expense).
    private func matchesSharedFilters(_ snap: TransactionSnapshot) -> Bool {
        if let id = selectedAccount?.id, snap.accountID != id { return false }
        if let cat = selectedCategory {
            if cat == .uncategorized {
                if snap.effectiveCategory != nil { return false }
            } else if snap.effectiveCategory != cat {
                return false
            }
        }
        if let sub = selectedSubcategory, snap.effectiveSubcategory != sub { return false }
        if !snap.matches(searchText: searchText) { return false }
        return true
    }

    private func recomputeFilteredTransactions() {
        let upperBound = nextMonthAfterEnd
        let lowerBound = dateFrom
        let filtered = viewModel.transactionsByDateDesc.filter { snap in
            guard matchesSharedFilters(snap) else { return false }
            if let type = selectedType, snap.effectiveType != type { return false }
            if snap.date < lowerBound || snap.date >= upperBound { return false }
            return true
        }
        cachedTransactions = filtered.sorted(by: sortsBefore)
    }

    /// Rebuilds the flow range chart's metrics from the shared-filtered snapshots (category,
    /// subcategory, account, search) — deliberately ignoring the date-range and type filters,
    /// so the chart always spans every month and shows both income + expense. Spans the full
    /// `globalStart…globalEnd` range so month slots stay fixed as the filter changes.
    private func recomputeChartMetrics() {
        guard let start = viewModel.globalStartMonth, let end = viewModel.globalEndMonth else {
            cachedChartMetrics = []
            return
        }
        let filtered = viewModel.transactionsByDateDesc.filter(matchesSharedFilters)
        cachedChartMetrics = AppViewModel.flowMetrics(from: filtered, start: start, end: end)
    }

    /// Orders two snapshots by the active sort field/direction, always breaking ties by
    /// date descending (newest first). Amount sorts by absolute magnitude.
    private func sortsBefore(_ a: TransactionSnapshot, _ b: TransactionSnapshot) -> Bool {
        let primary: ComparisonResult
        switch sortField {
        case .date:
            primary = a.date == b.date ? .orderedSame : (a.date < b.date ? .orderedAscending : .orderedDescending)
        case .description:
            primary = a.details.localizedStandardCompare(b.details)
        case .amount:
            let am = abs(a.effectiveAmount), bm = abs(b.effectiveAmount)
            primary = am == bm ? .orderedSame : (am < bm ? .orderedAscending : .orderedDescending)
        }
        if primary != .orderedSame {
            return sortAscending ? primary == .orderedAscending : primary == .orderedDescending
        }
        return a.date > b.date  // tie-break: newest first
    }

    /// Shared tap handler for the Expenses/Income breakdown cards: toggles the page's
    /// category filter (tapping the active category clears it) and drops any stale
    /// subcategory filter, mirroring the category Menu.
    private func selectCategory(_ tapped: CategoryID) {
        if selectedCategory == tapped {
            selectedCategory = nil          // toggle off → back to "all"
        } else {
            selectedCategory = tapped
        }
        selectedSubcategory = nil           // mirror the Menu; avoid stale sub-filter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                SectionContainer(title: "Expense by Category") { breakdown(.expense) }
                SectionContainer(title: "Income by Category") { breakdown(.income) }
                    .frame(width: sideColumnWidth)
            }

            HStack(alignment: .top, spacing: 12) {
                SectionContainer(title: showingReimbursements ? "Reimbursements" : "Transactions") {
                    if showingReimbursements { reimbursementsContent } else { transactionsContent }
                }
                    .frame(height: monthRangeCardHeight)
                SectionContainer(title: "Monthly Cash Flow") { periodContent }
                    .frame(width: sideColumnWidth)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        monthRangeCardHeight = $0
                    }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
        .onAppear {
            if !initialized, !viewModel.transactionsByDateDesc.isEmpty {
                initialized = true
                setDefaultDateRange()
                recomputeFilteredTransactions()
                recomputeChartMetrics()
            }
        }
        .onChange(of: viewModel.dataVersion) {
            if !initialized, !viewModel.transactionsByDateDesc.isEmpty {
                initialized = true
                setDefaultDateRange()
            }
            recomputeFilteredTransactions()
            recomputeChartMetrics()
        }
        .onChange(of: searchText) {
            recomputeFilteredTransactions()
            recomputeChartMetrics()
        }
        .onChange(of: dateFrom) { recomputeFilteredTransactions() }
        .onChange(of: dateTo) { recomputeFilteredTransactions() }
        .onChange(of: selectedAccount?.id) {
            recomputeFilteredTransactions()
            recomputeChartMetrics()
        }
        .onChange(of: selectedType) { recomputeFilteredTransactions() }
        .onChange(of: selectedCategory) {
            recomputeFilteredTransactions()
            recomputeChartMetrics()
        }
        .onChange(of: selectedSubcategory) {
            recomputeFilteredTransactions()
            recomputeChartMetrics()
        }
        .onChange(of: sortField) { recomputeFilteredTransactions() }
        .onChange(of: sortAscending) { recomputeFilteredTransactions() }
        .sheet(item: $detailRequest) { request in
            TransactionDetailSheet(request: request)
                .environment(viewModel)
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: CSVExporter.suggestedFilename()
        ) { _ in }
    }

    // MARK: - Sections

    private func breakdown(_ type: TransactionType) -> some View {
        CategoryBreakdownCard(
            snapshots: cachedTransactions,
            type: type,
            startMonth: dateFrom,
            endMonth: dateTo,
            onSelectCategory: selectCategory
        )
    }

    /// Month range picker. The vertical bar chart selects a single month on click and an inclusive
    /// range on shift+click (macOS); it drives `dateFrom`/`dateTo`.
    /// Requires at least two months; a single-month dataset shows a placeholder instead.
    @ViewBuilder
    private var periodContent: some View {
        if let start = viewModel.globalStartMonth,
           let end = viewModel.globalEndMonth,
           start < end {
            MonthlyFlowRangeVerticalBarChart(
                startMonth: $dateFrom,
                endMonth: $dateTo,
                globalStart: start,
                globalEnd: end,
                metrics: cachedChartMetrics,
                visibleMonths: visibleRangeMonths,
                width: nil   // fill the side column
            )
        } else {
            Text("Only one month of data")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Pinned header (filter / download / search) above the scrolling transaction list.
    private var transactionsContent: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                resetButton
                filterMenu
                downloadButton
                reimbursementsToggle
                searchPill
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(cachedTransactions) { snap in
                        TransactionCard(
                            snapshot: snap,
                            onCategoryTap: { openDetail(snap, focus: .category) },
                            onTap: { openDetail(snap, focus: .edit) }
                        ) {
                            menuItems(for: snap)
                        }
                    }
                }.padding(.trailing, 8)
            }
        }
    }

    /// Reimbursements review in place of the list. The transaction filters don't apply to it,
    /// so the header carries only the toggle back.
    private var reimbursementsContent: some View {
        VStack(spacing: 8) {
            HStack {
                reimbursementsToggle
                Spacer()
            }
            ReimbursementReviewView()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A transaction row's actions, shown in its right-click `.contextMenu`. Mirrors
    /// `ReserveCardView.menuItems`. Expense rows additionally get exactly one
    /// reimburse entry, reflecting current link state (US4). Every item opens the
    /// one-stop `TransactionDetailSheet`, landing on the matching section.
    @ViewBuilder
    private func menuItems(for snap: TransactionSnapshot) -> some View {
        Button("Edit", systemImage: "pencil") { openDetail(snap, focus: .edit) }
        Button("Change Category", systemImage: "tag") { openDetail(snap, focus: .category) }
        if snap.effectiveType == .expense {
            if viewModel.reimbursedExpenseHashes.contains(snap.id) {
                Button("View Reimbursement", systemImage: "link") {
                    openDetail(snap, focus: .reimbursement)
                }
            } else {
                Button("Reimburse Expense", systemImage: "arrow.uturn.backward.circle") {
                    openDetail(snap, focus: .reimbursement)
                }
            }
            // Use reserve funds against this expense (hidden when there are no
            // reserves to draw from).
            if !viewModel.reserves.isEmpty {
                if viewModel.usedTransactionIDs.contains(snap.id) {
                    Button("View Usage", systemImage: "cart") {
                        openDetail(snap, focus: .reserve)
                    }
                } else {
                    Button("Use Funds", systemImage: "cart") {
                        openDetail(snap, focus: .reserve)
                    }
                }
            }
        }
    }

    private func openDetail(_ snap: TransactionSnapshot, focus: TransactionDetailFocus) {
        detailRequest = TransactionDetailRequest(fallback: snap.transaction, focus: focus)
    }

    // MARK: - Header

    private var resetButton: some View {
        Button {
            resetFilters()
        } label: {
            Text("Reset")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hasActiveFilters ? Color.accentColor : .secondary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .glassEffect(in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Reset filters, date range, and sort to defaults")
    }

    private var filterMenu: some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(hasActiveFilters ? Color.accentColor : .secondary)
                .frame(width: 28, height: 28)
                .glassEffect(in: Circle())
                .contentShape(Circle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var downloadButton: some View {
        Button {
            exportDocument = TransactionsCSVDocument(
                csv: CSVExporter.makeCSV(from: cachedTransactions, categories: viewModel.categories)
            )
            isExporterPresented = true
        } label: {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .glassEffect(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(cachedTransactions.isEmpty)
        .help("Export filtered transactions to CSV")
    }

    private var reimbursementsToggle: some View {
        Button {
            showingReimbursements.toggle()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(showingReimbursements ? Color.accentColor : .secondary)
                .frame(width: 28, height: 28)
                .glassEffect(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(showingReimbursements ? "Back to transactions" : "Reimbursements — review and unlink")
    }

    private var searchPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search transactions...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 620)
        .glassEffect(in: Capsule())
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var menuContent: some View {
        Menu("Account") {
            checkmarkRow("All Accounts", isSelected: selectedAccount == nil) {
                selectedAccount = nil
            }
            ForEach(viewModel.accounts) { account in
                checkmarkRow(account.name, isSelected: selectedAccount?.id == account.id) {
                    selectedAccount = account
                }
            }
        }

        Menu("Type") {
            checkmarkRow("All Types", isSelected: selectedType == nil) {
                selectedType = nil
            }
            ForEach(TransactionType.allCases) { type in
                checkmarkRow(type.displayName, isSelected: selectedType == type) {
                    selectedType = type
                }
            }
        }

        Menu("Category") {
            checkmarkRow("All Categories", isSelected: selectedCategory == nil && selectedSubcategory == nil) {
                selectedCategory = nil
                selectedSubcategory = nil
            }
            Divider()
            checkmarkRow("Uncategorized", isSelected: selectedCategory == .uncategorized) {
                selectedCategory = .uncategorized
                selectedSubcategory = nil
            }
            Divider()
            ForEach(viewModel.rootCategories(), id: \.id) { cat in
                let leaves = viewModel.leafCategories(under: cat.id)
                if leaves.isEmpty {
                    let isSelected = selectedCategory == CategoryID(rawValue: cat.id) && selectedSubcategory == nil
                    Button {
                        selectedCategory = CategoryID(rawValue: cat.id)
                        selectedSubcategory = nil
                    } label: {
                        if isSelected {
                            Label(cat.displayName, systemImage: "checkmark")
                        } else {
                            categoryLabel(cat)
                        }
                    }
                } else {
                    Menu {
                        checkmarkRow("All \(cat.displayName)", isSelected: selectedCategory == CategoryID(rawValue: cat.id) && selectedSubcategory == nil) {
                            selectedCategory = CategoryID(rawValue: cat.id)
                            selectedSubcategory = nil
                        }
                        ForEach(leaves, id: \.id) { sub in
                            checkmarkRow(sub.displayName, isSelected: selectedSubcategory == SubcategoryID(rawValue: sub.id)) {
                                selectedCategory = CategoryID(rawValue: cat.id)
                                selectedSubcategory = SubcategoryID(rawValue: sub.id)
                            }
                        }
                    } label: {
                        categoryLabel(cat)
                    }
                }
            }
        }

        Menu("Sort") {
            sortRow(.date)
            sortRow(.description)
            sortRow(.amount)
        }

        Divider()

        Button("Reset") { resetFilters() }
    }

    /// Clears every filter, date range, and sort back to defaults. Shared by the
    /// filter Menu's Reset row and the header's Reset button.
    private func resetFilters() {
        setDefaultDateRange()
        selectedAccount = nil
        selectedType = nil
        selectedCategory = nil
        selectedSubcategory = nil
        searchText = ""
        sortField = .date
        sortAscending = false
    }

    /// A sort field row. Tapping an inactive field selects it at its default direction;
    /// tapping the active field flips direction. The leading arrow doubles as the
    /// selection indicator (arrow present = this field is active).
    @ViewBuilder
    private func sortRow(_ field: SortField) -> some View {
        Button {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = field.defaultAscending
            }
        } label: {
            if sortField == field {
                Label(field.title, systemImage: sortAscending ? "chevron.up" : "chevron.down")
            } else {
                Text(field.title)
            }
        }
    }

    @ViewBuilder
    private func checkmarkRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    /// Category menu label whose symbol is tinted with the category's own color.
    @ViewBuilder
    private func categoryLabel(_ cat: Category) -> some View {
        Label {
            Text(cat.displayName)
        } icon: {
            Image(systemName: cat.symbol)
                .foregroundStyle(Color(hex: cat.color))
        }
    }

    // MARK: - Default Date Range

    private func setDefaultDateRange() {
        guard let start = viewModel.globalStartMonth,
              let end = viewModel.globalEndMonth else { return }
        // Default to the full range of available data.
        dateFrom = start
        dateTo = end
    }
}
