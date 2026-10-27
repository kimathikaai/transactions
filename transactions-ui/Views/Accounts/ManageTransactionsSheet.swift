import SwiftUI

/// Per-account modal for manually adding and deleting transactions, an
/// alternative to CSV upload. Top: an input row (date, signed amount, details)
/// plus an Add button. Bottom: a searchable, headerless list of the account's
/// transactions rendered as `[delete] date · details · amount`, each deletable
/// with a confirmation.
///
/// Adds append a CSV line and deletes rewrite the CSV without a line — both go
/// through `AppViewModel`, which reparses so the derived transaction list and
/// balances update immediately.
struct ManageTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var viewModel

    let account: Account

    @State private var date = Date()
    @State private var amountText = ""
    @State private var details = ""
    @State private var searchText = ""
    @State private var pendingDelete: Transaction?

    /// Signed amount parsed from the input, or nil when blank/non-numeric.
    private var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var canAdd: Bool {
        guard let amount = parsedAmount, amount != 0 else { return false }
        return !details.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The account's transactions, newest first, filtered by the search text.
    private var visibleTransactions: [Transaction] {
        let txs = viewModel.allTransactions
            .filter { $0.accountID == account.id }
            .sorted { $0.date > $1.date }
        let terms = searchText.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return txs }
        return txs.filter { tx in
            let amountString = String(format: "%.2f", abs(tx.effectiveAmount))
            let fields = [tx.details, tx.effectiveNotes ?? "", amountString]
            return terms.allSatisfy { term in
                fields.contains { $0.localizedCaseInsensitiveContains(term) }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            inputSection
            Divider()
            searchField
            transactionList
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 520)
        .confirmationDialog(
            "Delete this transaction?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { tx in
            Button("Delete", role: .destructive) {
                viewModel.deleteTransaction(tx, from: account)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { tx in
            Text("\(tx.details) — \(tx.effectiveAmount, format: .cad). This can't be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transactions")
                    .font(.headline)
                Text(account.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                TextField("Amount (− expense, + income)", text: $amountText)
                    .frame(maxWidth: 200)
                    .onSubmit(addIfPossible)
            }
            TextField("Details", text: $details)
                .onSubmit(addIfPossible)
            Button(action: addIfPossible) {
                Label("Add Transaction", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canAdd)
        }
    }

    private func addIfPossible() {
        guard canAdd, let amount = parsedAmount else { return }
        let ok = viewModel.addManualTransaction(
            date: date,
            signedAmount: amount,
            details: details,
            into: account
        )
        if ok {
            amountText = ""
            details = ""
        }
    }

    // MARK: - List

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search transactions...", text: $searchText)
                .textFieldStyle(.plain)
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
        .padding(8)
        .background(Color.gray.opacity(0.1), in: .rect(cornerRadius: 6))
    }

    private var transactionList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(visibleTransactions) { tx in
                    ManualTransactionRow(transaction: tx) { pendingDelete = tx }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// One list row: a leading delete button, the date, the details, and the signed
/// amount colored by direction.
private struct ManualTransactionRow: View {
    let transaction: Transaction
    var onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        // CSV dates are anchored at 00:00 UTC — render in UTC so the day matches.
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private var amountColor: Color {
        transaction.effectiveAmount < 0 ? .expense : .income
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete transaction")

            Text(Self.dateFormatter.string(from: transaction.date))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(transaction.details)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(transaction.effectiveAmount, format: .cad)
                .foregroundStyle(amountColor)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .hoverHighlight(in: .rect(cornerRadius: 6))
    }
}

#Preview {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    return ManageTransactionsSheet(
        account: Account(name: "Chequing", type: .chequing, initialBalance: 0, csvFileName: "chequing.csv")
    )
    .environment(AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    ))
}
