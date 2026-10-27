import SwiftUI

/// View and unlink an expense's reserve usage — the transactions-list companion
/// to `ReserveUseSheet`. Echoes the expense for orientation, shows which reserve
/// (and source account) it was used against and for how much, and offers a
/// single reversible "Unlink" action. Styled after `ViewReimbursementSheet`:
/// clear presentation background, 16pt continuous material cards, glass footer
/// buttons, `Color.spent` accent. Unlinking is not destructive-red because
/// re-using is the undo.
struct ViewUsageSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let expense: Transaction

    // The `.use` event for this expense; nil only if it was unlinked out from
    // under us (e.g. deleted from the Reserves-page Activity table).
    private var event: ReserveEvent? {
        viewModel.usageEvent(forExpense: expense.contentHash)
    }

    private var reserve: Reserve? {
        guard let id = event?.reserveID else { return nil }
        return viewModel.reserves.first { $0.id == id }
    }

    private var source: Account? {
        guard let id = event?.accountID else { return nil }
        return viewModel.accounts.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            expenseCard
            usedAgainstCard
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

    // "Used against" + capsule: reserve (emoji · name) from source account, with
    // the used amount in bold.
    private var usedAgainstCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Used against")
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
            if let reserve {
                Text("\(reserve.emoji) \(reserve.name)")
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let source {
                    Text("· from \(source.name)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Text("(usage no longer available)")
                    .foregroundStyle(.secondary)
            }
            if let event {
                Text(event.amount, format: .cad)
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

            Button("Unlink \((event?.amount ?? 0).formatted(.cad))", action: unlink)
                .buttonStyle(.glassProminent)
                .tint(Color.spent)
                .keyboardShortcut(.defaultAction)
                .disabled(event == nil)
        }
    }

    private func unlink() {
        if let event {
            viewModel.deleteReserveEvent(id: event.id)
        }
        dismiss()
    }
}
