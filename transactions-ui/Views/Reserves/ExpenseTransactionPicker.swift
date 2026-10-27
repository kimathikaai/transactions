import SwiftUI

/// A searchable list of expense transactions, presented as a secondary sheet by
/// `ReserveUseSheet`. Rows stay selectable even when already linked to a
/// use — the parent sheet surfaces the "already used" error inline — but
/// linked rows are marked so the choice is informed.
struct ExpenseTransactionPicker: View {
    let transactions: [TransactionSnapshot]   // expense-only, newest-first
    let linkedHashes: Set<String>
    let onSelect: (TransactionSnapshot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [TransactionSnapshot] {
        transactions.filter { $0.matches(searchText: query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { tx in
                Button {
                    onSelect(tx)
                    dismiss()
                } label: {
                    row(tx)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Link a Transaction")
            .searchable(text: $query, prompt: "Search details, notes, amount")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    private func row(_ tx: TransactionSnapshot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.details)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: tx.date))
                    if let account = tx.accountName {
                        Text("·")
                        Text(account)
                    }
                    if linkedHashes.contains(tx.id) {
                        Text("·")
                        Text("linked")
                            .foregroundStyle(Color.spent)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(abs(tx.effectiveAmount).formatted(.cad))
                .font(.callout)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    /// UTC-anchored short date, matching the rest of the reserve UI.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
