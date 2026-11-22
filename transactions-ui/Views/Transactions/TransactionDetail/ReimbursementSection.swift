import SwiftUI

/// The modal's Reimbursement section for an expense: the incomes that pay it
/// back. Shows the reimbursed / remaining total, each covering income with Open
/// (re-targets the modal at it) and Unlink, and a picker that links one income
/// at a time — selecting alone changes nothing, because a link moves money
/// between pools. The picker stays until the expense is fully reimbursed.
/// Each link takes `min(the expense's remainder, the income's remaining pool)`.
struct ReimbursementSection: View {
    @Environment(AppViewModel.self) private var viewModel

    let expense: Transaction
    @Binding var isExpanded: Bool
    /// Re-targets the modal at the source income's hash.
    let onOpen: (String) -> Void

    @State private var query = ""
    // Selected income by contentHash — persists even if a query later hides it.
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

    private var links: [ReimbursementLink] {
        viewModel.reimbursementLinks(forExpense: expense.contentHash)
    }

    private var expenseAmount: Double { abs(expense.effectiveAmount) }
    private var reimbursed: Double { viewModel.reimbursed(forExpense: expense.contentHash) }
    private var expenseLeft: Double {
        viewModel.unreimbursed(forExpense: expense.contentHash, amount: expenseAmount)
    }

    private var summary: String {
        "Reimbursed \(reimbursed.formatted(.cad)) of \(expenseAmount.formatted(.cad)) · \(expenseLeft.formatted(.cad)) remaining"
    }

    var body: some View {
        DetailSection(
            title: "Reimbursement",
            descriptor: "Did someone pay you back for this? Link it to the income that covered it so it nets out of your flow.",
            status: links.isEmpty ? "Not linked" : summary,
            statusTint: links.isEmpty ? .neutral : .done,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !links.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(links, id: \.reimbursementHash) { link in
                            linkedCapsule(link)
                        }
                    }
                }
                if expenseLeft < 0.01 {
                    Text("Fully reimbursed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    picker
                }
            }
        }
    }

    // MARK: - Linked

    private func linkedCapsule(_ link: ReimbursementLink) -> some View {
        let source = viewModel.transaction(withHash: link.reimbursementHash)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let source {
                    Text(source.details)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(source.details)
                    Text("\(Self.dateFormatter.string(from: source.date)) · reimbursed \(link.amount.formatted(.cad))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("(source no longer available)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("reimbursed \(link.amount.formatted(.cad))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if source != nil {
                    Button("Open") { onOpen(link.reimbursementHash) }
                }
                // Not destructive-red: re-linking is the undo.
                Button("Unlink") {
                    viewModel.unlinkReimbursement(expenseHash: expense.contentHash,
                                                  incomeHash: link.reimbursementHash)
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
        viewModel.incomeTransactions.filter { $0.matches(searchText: query) }
    }

    private func remaining(_ snap: TransactionSnapshot) -> Double {
        viewModel.remaining(forReimbursement: snap.id, capacity: abs(snap.effectiveAmount))
    }

    private var selected: TransactionSnapshot? {
        guard let selectedID else { return nil }
        return viewModel.incomeTransactions.first { $0.id == selectedID }
    }

    private var reimburseAmount: Double? {
        selected.map { min(expenseLeft, remaining($0)) }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            if viewModel.incomeTransactions.isEmpty {
                Text("No income to reimburse from")
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
                    Text("No matching income")
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
        // A source with nothing left, or one already linked here, can't be picked.
        let isUnavailable = remaining(snap) < 0.01
            || viewModel.isReimbursementLinked(expenseHash: expense.contentHash, incomeHash: snap.id)
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
        .disabled(isUnavailable)
        .opacity(isUnavailable ? 0.4 : 1)
    }

    private func linkSelected() {
        guard let selected else { return }
        if viewModel.linkReimbursement(expense: expense, toIncome: selected.transaction) {
            selectedID = nil
        }
    }
}
