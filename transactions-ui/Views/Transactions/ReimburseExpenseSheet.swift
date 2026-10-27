import SwiftUI

/// Modal 1 of US4 — pick which reimbursement income covers an expense. The
/// reimbursed amount is automatic (`min(|expense|, the source's remaining
/// pool)`), so there is nothing to type: the user searches, selects one income,
/// and commits. Styled after `ReserveTransferSheet`: clear presentation
/// background, 16pt continuous material cards, glass footer, income-green accent.
struct ReimburseExpenseSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let expense: Transaction

    @State private var query = ""
    // Selected income by contentHash — persists even if a query later hides it.
    @State private var selectedID: String?

    // Column widths, shared by the header row and each candidate row so they align.
    private let dateWidth: CGFloat = 96
    private let amountWidth: CGFloat = 90

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        // CSV dates are anchored at 00:00 UTC — render in UTC (see TransactionCard).
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - Derived

    private var expenseAmount: Double { abs(expense.effectiveAmount) }

    // All income newest-first (the full candidate pool, independent of the query).
    private var allIncome: [TransactionSnapshot] { viewModel.incomeTransactions }

    private var filtered: [TransactionSnapshot] {
        allIncome.filter { $0.matches(searchText: query) }
    }

    private func capacity(_ snap: TransactionSnapshot) -> Double {
        abs(snap.effectiveAmount)
    }

    private func remaining(_ snap: TransactionSnapshot) -> Double {
        viewModel.remaining(forReimbursement: snap.id, capacity: capacity(snap))
    }

    // A source with nothing left can't be picked (US7).
    private func isFullyClaimed(_ snap: TransactionSnapshot) -> Bool {
        remaining(snap) < 0.01
    }

    private var selected: TransactionSnapshot? {
        guard let id = selectedID else { return nil }
        return allIncome.first { $0.id == id }
    }

    // The amount that would be reimbursed for the current selection (US1/US2/US8).
    private var reimburseAmount: Double? {
        guard let selected else { return nil }
        return min(expenseAmount, remaining(selected))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            expenseCard
            candidatesCard
            footer
        }
        .padding(20)
        .frame(minWidth: 460)
        .presentationBackground(.clear)
    }

    // MARK: - Expense context

    private var expenseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(expense.details)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(expenseAmount.formatted(.cad))
                .font(.title3.monospacedDigit())
                .foregroundStyle(Color.expense)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Candidates (search + header + table)

    private var candidatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField
            if allIncome.isEmpty {
                emptyState("No income to reimburse from")
            } else {
                Divider()
                columnHeader
                table
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
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
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Date").frame(width: dateWidth, alignment: .leading)
            Text("Details").frame(maxWidth: .infinity, alignment: .leading)
            Text("Capacity").frame(width: amountWidth, alignment: .trailing)
            Text("Remaining").frame(width: amountWidth, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if filtered.isEmpty {
                    emptyState("No matching income")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                } else {
                    ForEach(filtered) { snap in
                        row(snap)
                    }
                }
            }
        }
        .frame(height: 260)
    }

    private func row(_ snap: TransactionSnapshot) -> some View {
        let claimed = isFullyClaimed(snap)
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
                Text(capacity(snap).formatted(.cad))
                    .frame(width: amountWidth, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(remaining(snap).formatted(.cad))
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
        .disabled(claimed)
        .opacity(claimed ? 0.4 : 1)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let reimburseAmount, reimburseAmount < expenseAmount {
                Text("Reimburses \(reimburseAmount.formatted(.cad)) of this \(expenseAmount.formatted(.cad)) expense.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

            Button("Reimburse \((reimburseAmount ?? 0).formatted(.cad))", action: reimburse)
                .buttonStyle(.glassProminent)
                .tint(.income)
                .keyboardShortcut(.defaultAction)
                .disabled(reimburseAmount == nil)
        }
    }

    private func reimburse() {
        guard let selected else { return }
        viewModel.linkReimbursement(expense: expense, toIncome: selected.transaction)
        dismiss()
    }
}
