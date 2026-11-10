import SwiftUI

/// The one-stop transaction modal: the original bank row on top, then
/// collapsible Category, Notes, Reimbursement and Reserve sections. Every change
/// saves as it's made, and the modal re-reads its transaction by `contentHash`
/// on each render, so it keeps showing live state even after the row drops out
/// of the filtered list behind it.
struct TransactionDetailSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let request: TransactionDetailRequest

    @State private var expanded: Set<TransactionDetailSection> = []

    private var transaction: Transaction {
        viewModel.transaction(withHash: request.hash) ?? request.fallback
    }

    /// Reimbursement and Reserve links only exist for expenses.
    private var isExpense: Bool { transaction.effectiveType == .expense }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OriginalTransactionCard(transaction: transaction)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CategorySection(transaction: transaction, isExpanded: binding(.category))
                    NotesSection(transaction: transaction, isExpanded: binding(.notes))
                    if isExpense {
                        ReimbursementSection(expense: transaction, isExpanded: binding(.reimbursement))
                        if !viewModel.reserves.isEmpty {
                            ReserveUseSection(expense: transaction, isExpanded: binding(.reserve))
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .padding(20)
        .frame(width: 620)
        .frame(minHeight: 420, idealHeight: 640, maxHeight: 640)
        .presentationBackground(.clear)
        .onAppear {
            viewModel.lastSaveError = nil
            let tx = transaction
            expanded = TransactionDetailSection.initialExpansion(
                focus: request.focus,
                isUncategorized: tx.effectiveCategory == nil,
                hasNotes: !(tx.effectiveNotes ?? "").isEmpty,
                isReimbursed: viewModel.reimbursementLink(forExpense: tx.contentHash) != nil,
                isUsed: viewModel.usedTransactionIDs.contains(tx.contentHash)
            )
        }
    }

    private func binding(_ section: TransactionDetailSection) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(section) },
            set: { isOn in
                if isOn { expanded.insert(section) } else { expanded.remove(section) }
            }
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = viewModel.lastSaveError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Label("Changes save as you make them", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // Escape closes (everything is already saved); deliberately not
            // Return, which would close the modal from the search/note fields.
            Button("Done") { dismiss() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// The bank row as imported — read-only and always shown. The description wraps
/// onto as many lines as it needs; the amount is signed and tinted by the
/// current effective type.
private struct OriginalTransactionCard: View {
    @Environment(AppViewModel.self) private var viewModel
    let transaction: Transaction

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        // Dates originate from BankCsvParser anchored at 00:00 UTC — render
        // in UTC so a 2026-06-29 CSV row displays as Jun 29 in any local TZ.
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Original transaction · from the bank CSV, never changes")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Vertical fixedSize stops the sheet's ideal-height sizing from
            // truncating the description to one line.
            Text(transaction.details)
                .font(.callout)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                field("Date", Self.dateFormatter.string(from: transaction.date))
                field("Account", viewModel.account(id: transaction.accountID)?.name ?? "—")
                Spacer(minLength: 0)
                Text(transaction.effectiveAmount, format: .cad)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(amountTint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCardBackground()
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
        }
    }

    private var amountTint: Color {
        switch transaction.effectiveType {
        case .expense, .transfer_out: return .expense
        case .income, .transfer_in:   return .income
        }
    }
}
