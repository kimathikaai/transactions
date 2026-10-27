import SwiftUI

/// Modal 2 of US4 — view and unlink an expense's reimbursement. Echoes the
/// expense for orientation, shows which income reimbursed it (and for how much)
/// in a capsule, and offers a single reversible "Unlink and Release" action.
/// Styled after `ReserveTransferSheet` / `ReserveEditSheet`: clear presentation
/// background, 16pt continuous material cards, glass footer buttons, income-green
/// accent. Unlinking is not destructive-red because re-linking is the undo.
struct ViewReimbursementSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let expense: Transaction

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        // CSV dates are anchored at 00:00 UTC — render in UTC (see TransactionCard).
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    // The link for this expense; nil only if it was unlinked out from under us.
    private var link: ReimbursementLink? {
        viewModel.reimbursementLink(forExpense: expense.contentHash)
    }

    // The reimbursement income, resolved live by contentHash. Nil = dangling
    // (its CSV row changed, or it was removed) → US13 "(source no longer available)".
    private var source: Transaction? {
        guard let hash = link?.reimbursementHash else { return nil }
        return viewModel.allTransactions.first { $0.contentHash == hash }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            expenseCard
            reimbursedByCard
            footer
        }
        .padding(20)
        .frame(minWidth: 460)
        .presentationBackground(.clear)
    }

    // MARK: - Cards

    // Expense context — details + amount, echoed for orientation.
    private var expenseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(expense.details)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(abs(expense.effectiveAmount).formatted(.cad))
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

    // "Reimbursed by" + capsule: source income (details · date) with the
    // reimbursed amount in bold, à la ReserveEditSheet.pill.
    private var reimbursedByCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reimbursed by")
                .font(.caption)
                .foregroundStyle(.secondary)
            capsule
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private var capsule: some View {
        HStack(spacing: 6) {
            if let source {
                Text("\(source.details) · \(Self.dateFormatter.string(from: source.date))")
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("(source no longer available)")
                    .foregroundStyle(.secondary)
            }
            if let link {
                Text(link.amount, format: .cad)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button("Close") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

            Button("Unlink and Release \((link?.amount ?? 0).formatted(.cad))", action: unlink)
                .buttonStyle(.glassProminent)
                .tint(.income)
                .keyboardShortcut(.defaultAction)
                .disabled(link == nil)
        }
    }

    private func unlink() {
        viewModel.unlinkReimbursement(expenseHash: expense.contentHash)
        dismiss()
    }
}

// MARK: - Previews

/// Seeds a reimbursement link for `expenseHash` before building the VM so the
/// sheet renders with a live link. No transactions are loaded, so the source
/// resolves as dangling — exercising the "(source no longer available)" path.
private func previewViewModel(expenseHash: String) -> AppViewModel {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    let reimbursementStore = ReimbursementStore(fileURL: dir.appendingPathComponent("reimbursements.json"))
    try? reimbursementStore.upsert(
        expenseHash: expenseHash,
        record: ReimbursementLink(reimbursementHash: "income-hash", amount: 30)
    )
    return AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json")),
        reimbursementStore: reimbursementStore
    )
}

#Preview("Dangling source") {
    let expense = Transaction(
        contentHash: "expense-hash",
        date: Date(timeIntervalSince1970: 1_700_000_000),
        details: "Hotel — work trip",
        debit: 100, credit: 0,
        transactionType: .expense,
        accountID: UUID()
    )
    return ViewReimbursementSheet(expense: expense)
        .frame(width: 500)
        .padding(40)
        .environment(previewViewModel(expenseHash: expense.contentHash))
}
