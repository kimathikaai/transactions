import SwiftUI

/// A searchable list of transactions, presented as a secondary sheet by the
/// reserve sheets (`ReserveUseSheet` passes expenses only; add/release linking
/// passes every transaction). Rows in `linkedHashes` stay selectable — the
/// parent surfaces any "already used" error inline — but are marked so the
/// choice is informed.
struct TransactionPicker: View {
    let transactions: [TransactionSnapshot]   // candidate transactions, newest-first
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
            Text(tx.signedAmountText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(tx.amountTint)
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
