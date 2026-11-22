import SwiftUI

/// The modal's Reimbursement section for an income: the expenses it pays back.
/// Shows the pool (covered / remaining), each covered expense with Open and
/// Unlink, and a picker that links one expense at a time — the picker stays
/// open so several can be linked in a row. Rows show each expense's
/// unreimbursed remainder; fully reimbursed expenses, and ones already linked
/// to this income, are greyed out. Each link takes `min(the expense's
/// remainder, the remaining pool)`.
struct IncomeReimbursementSection: View {
    @Environment(AppViewModel.self) private var viewModel

    let income: Transaction
    @Binding var isExpanded: Bool
    /// Re-targets the modal at the given expense hash.
    let onOpen: (String) -> Void

    @State private var query = ""
    // Selected expense by contentHash — persists even if a query later hides it.
    @State private var selectedID: String?

    private let dateWidth: CGFloat = 90
    private let amountWidth: CGFloat = 90

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        // CSV dates are anchored at 00:00 UTC — render in UTC (see TransactionCard).
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var covered: [(expenseHash: String, link: ReimbursementLink)] {
        viewModel.reimbursementLinks(forIncome: income.contentHash)
    }

    private var capacity: Double { abs(income.effectiveAmount) }
    private var claimed: Double { viewModel.claimed(forReimbursement: income.contentHash) }
    private var remaining: Double {
        viewModel.remaining(forReimbursement: income.contentHash, capacity: capacity)
    }

    private var poolSummary: String {
        "Covered \(claimed.formatted(.cad)) of \(capacity.formatted(.cad)) · \(remaining.formatted(.cad)) remaining"
    }

    var body: some View {
        DetailSection(
            title: "Reimbursement",
            descriptor: "Did this pay you back for something? Link the expenses it covered so they net out of your flow.",
            status: covered.isEmpty ? "Not linked" : poolSummary,
            statusTint: covered.isEmpty ? .neutral : .done,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !covered.isEmpty {
                    Text(poolSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(covered, id: \.expenseHash) { entry in
                            coveredCapsule(expenseHash: entry.expenseHash, link: entry.link)
                        }
                    }
                }
                if remaining < 0.01 {
                    Text("Fully claimed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    picker
                }
            }
        }
    }

    // MARK: - Covered expenses

    private func coveredCapsule(expenseHash: String, link: ReimbursementLink) -> some View {
        let expense = viewModel.transaction(withHash: expenseHash)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let expense {
                    Text(expense.details)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(expense.details)
                    Text("\(Self.dateFormatter.string(from: expense.date)) · reimbursed \(link.amount.formatted(.cad))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("(expense no longer available)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("reimbursed \(link.amount.formatted(.cad))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if expense != nil {
                    Button("Open") { onOpen(expenseHash) }
                }
                // Not destructive-red: re-linking is the undo.
                Button("Unlink") {
                    viewModel.unlinkReimbursement(expenseHash: expenseHash,
                                                  incomeHash: income.contentHash)
                }
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.income.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Picker

    private var filtered: [TransactionSnapshot] {
        viewModel.expenseTransactions.filter { $0.matches(searchText: query) }
    }

    private var selected: TransactionSnapshot? {
        guard let selectedID else { return nil }
        return viewModel.expenseTransactions.first { $0.id == selectedID }
    }

    /// What's left to reimburse on a candidate expense.
    private func expenseLeft(_ snap: TransactionSnapshot) -> Double {
        viewModel.unreimbursed(forExpense: snap.id, amount: abs(snap.effectiveAmount))
    }

    private var reimburseAmount: Double? {
        selected.map { min(expenseLeft($0), remaining) }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            if viewModel.expenseTransactions.isEmpty {
                Text("No expenses to reimburse")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                columnHeader
                table
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let reimburseAmount {
                    Text("Reimburses \(reimburseAmount.formatted(.cad))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Link", action: linkSelected)
                    .buttonStyle(.glassProminent)
                    .tint(.income)
                    .disabled(reimburseAmount == nil)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search details, notes, amount", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Date").frame(width: dateWidth, alignment: .leading)
            Text("Details").frame(maxWidth: .infinity, alignment: .leading)
            Text("Remaining").frame(width: amountWidth, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }

    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if filtered.isEmpty {
                    Text("No matching expenses")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                } else {
                    ForEach(filtered) { snap in
                        row(snap)
                    }
                }
            }
        }
        .frame(height: 180)
    }

    private func row(_ snap: TransactionSnapshot) -> some View {
        // A fully reimbursed expense, or one already linked here, is shown but can't be picked.
        let isUnavailable = expenseLeft(snap) < 0.01
            || viewModel.isReimbursementLinked(expenseHash: snap.id, incomeHash: income.contentHash)
        let isSelected = selectedID == snap.id
        let detailText = snap.accountName.map { "\(snap.details) · \($0)" } ?? snap.details
        return Button {
            selectedID = isSelected ? nil : snap.id
        } label: {
            HStack(spacing: 8) {
                Text(Self.dateFormatter.string(from: snap.date))
                    .frame(width: dateWidth, alignment: .leading)
                    .foregroundStyle(.secondary)
                Text(detailText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(detailText)
                Text(expenseLeft(snap).formatted(.cad))
                    .frame(width: amountWidth, alignment: .trailing)
            }
            .font(.callout)
            .monospacedDigit()
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.income.opacity(0.18) : .clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .opacity(isUnavailable ? 0.4 : 1)
    }

    private func linkSelected() {
        guard let selected else { return }
        if viewModel.linkReimbursement(expense: selected.transaction, toIncome: income) {
            selectedID = nil
        }
    }
}
