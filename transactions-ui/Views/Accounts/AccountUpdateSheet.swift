import SwiftUI

/// The per-account "Update" modal — the everyday way to bring an account up to
/// date. Built like `TransactionDetailSheet`: three collapsible cards.
///
/// - **CSV Upload** imports the bank's export through `csvUploadFlow` (file
///   picker → diff preview → commit). The modal stays open afterwards.
/// - **Add Transaction** appends one manual row (date, signed amount, details).
/// - **Edit Transactions** is a searchable list of the account's transactions.
///   Clicking a row opens `TransactionDetailSheet`; the trash button deletes it.
///
/// Every write goes through `AppViewModel`, which reparses, so the list, chips
/// and balances update immediately.
struct AccountUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var viewModel

    let account: Account

    @State private var expanded: Set<AccountUpdateSection> = [.csvUpload]
    @State private var isImporting = false
    @State private var detailRequest: TransactionDetailRequest?
    @State private var pendingDelete: Transaction?

    /// The account's transactions, newest first.
    private var accountTransactions: [Transaction] {
        viewModel.allTransactions
            .filter { $0.accountID == account.id }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        let transactions = accountTransactions
        VStack(alignment: .leading, spacing: 16) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CSVUploadSection(
                        latestDate: transactions.first?.date,
                        isExpanded: binding(.csvUpload),
                        onChooseFile: { isImporting = true }
                    )
                    AddTransactionSection(account: account, isExpanded: binding(.addTransaction))
                    EditTransactionsSection(
                        transactions: transactions,
                        isExpanded: binding(.editTransactions),
                        onEdit: { detailRequest = TransactionDetailRequest(fallback: $0, focus: .edit) },
                        onDelete: { pendingDelete = $0 }
                    )
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .padding(20)
        .frame(width: 620)
        .frame(minHeight: 420, idealHeight: 640, maxHeight: 640)
        .presentationBackground(.clear)
        .onAppear { viewModel.lastSaveError = nil }
        .csvUploadFlow(isPresented: $isImporting, account: account)
        .sheet(item: $detailRequest) { request in
            TransactionDetailSheet(request: request)
                .environment(viewModel)
        }
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

    private func binding(_ section: AccountUpdateSection) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(section) },
            set: { isOn in
                if isOn { expanded.insert(section) } else { expanded.remove(section) }
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Update")
                .font(.headline)
            Text(account.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = viewModel.lastSaveError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            // Escape closes; deliberately not Return, which would close the
            // modal from the Add Transaction and search fields.
            Button("Done") { dismiss() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// The Update modal's collapsible cards.
private enum AccountUpdateSection: Hashable {
    case csvUpload
    case addTransaction
    case editTransactions
}

/// CSV dates are anchored at 00:00 UTC — render in UTC so the day matches.
private let accountUpdateDateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM d, yyyy"
    fmt.timeZone = TimeZone(identifier: "UTC")
    return fmt
}()

// MARK: - CSV Upload

private struct CSVUploadSection: View {
    let latestDate: Date?
    @Binding var isExpanded: Bool
    var onChooseFile: () -> Void

    private var status: String {
        guard let latestDate else { return "No transactions yet" }
        return "Up to \(accountUpdateDateFormatter.string(from: latestDate))"
    }

    var body: some View {
        DetailSection(
            title: "CSV Upload",
            descriptor: "Import the bank's export. You'll review what gets added or removed before anything is saved.",
            status: status,
            statusTint: .neutral,
            isExpanded: $isExpanded
        ) {
            Button(action: onChooseFile) {
                Label("Choose CSV…", systemImage: "arrow.up.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }
}

// MARK: - Add Transaction

private struct AddTransactionSection: View {
    @Environment(AppViewModel.self) private var viewModel

    let account: Account
    @Binding var isExpanded: Bool

    @State private var date = Date()
    @State private var amountText = ""
    @State private var details = ""
    /// Rows added while this modal is open, for the status chip.
    @State private var addedCount = 0

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

    private var status: String {
        addedCount == 0 ? "None added" : "Added \(addedCount)"
    }

    var body: some View {
        DetailSection(
            title: "Add Transaction",
            descriptor: "Enter one row by hand — a negative amount is an expense, positive is income.",
            status: status,
            statusTint: addedCount == 0 ? .neutral : .done,
            isExpanded: $isExpanded
        ) {
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
                .buttonStyle(.glass)
                .disabled(!canAdd)
            }
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
            addedCount += 1
            amountText = ""
            details = ""
        }
    }
}

// MARK: - Edit Transactions

private struct EditTransactionsSection: View {
    /// The account's transactions, newest first.
    let transactions: [Transaction]
    @Binding var isExpanded: Bool
    var onEdit: (Transaction) -> Void
    var onDelete: (Transaction) -> Void

    @State private var searchText = ""

    /// `transactions` filtered by the search text (details, notes, amount).
    private var visibleTransactions: [Transaction] {
        let terms = searchText.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return transactions }
        return transactions.filter { tx in
            let amountString = String(format: "%.2f", abs(tx.effectiveAmount))
            let fields = [tx.details, tx.effectiveNotes ?? "", amountString]
            return terms.allSatisfy { term in
                fields.contains { $0.localizedCaseInsensitiveContains(term) }
            }
        }
    }

    private var status: String {
        transactions.count == 1 ? "1 transaction" : "\(transactions.count) transactions"
    }

    var body: some View {
        DetailSection(
            title: "Edit Transactions",
            descriptor: "Click a transaction to change its category, notes, reimbursement or reserve use.",
            status: status,
            statusTint: .neutral,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 8) {
                searchField
                LazyVStack(spacing: 2) {
                    ForEach(visibleTransactions) { tx in
                        EditableTransactionRow(
                            transaction: tx,
                            onEdit: { onEdit(tx) },
                            onDelete: { onDelete(tx) }
                        )
                    }
                }
            }
        }
    }

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
}

/// One list row: a leading delete button, then the date, details and signed
/// amount (colored by direction). Clicking the row opens the transaction modal.
private struct EditableTransactionRow: View {
    let transaction: Transaction
    var onEdit: () -> Void
    var onDelete: () -> Void

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

            Button(action: onEdit) {
                HStack(spacing: 10) {
                    Text(accountUpdateDateFormatter.string(from: transaction.date))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)

                    Text(transaction.details)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(transaction.effectiveAmount, format: .cad)
                        .foregroundStyle(amountColor)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit transaction")
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
    return AccountUpdateSheet(
        account: Account(name: "Chequing", type: .chequing, initialBalance: 0, csvFileName: "chequing.csv")
    )
    .environment(AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    ))
}
