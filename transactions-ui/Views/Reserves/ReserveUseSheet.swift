import SwiftUI

/// A quick-action popup for using a reserve: linking a real expense
/// transaction that spent money held in the reserve. Styled after
/// `ReserveTransferSheet`. Money flows [Reserve] → [Source] (the held balance is
/// drawn down), and a transaction is linked to the movement. The source and the
/// linked transaction are chosen independently — the transaction may live on any
/// account (e.g. saved in Savings, spent on a credit card).
///
/// Opened from a reserve card: the reserve is fixed and the user picks the
/// transaction (and source). The transactions-list side lives in the transaction
/// modal's Reserve section (`ReserveActivitySection`).
struct ReserveUseSheet: View {
    let reserve: Reserve

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSourceID: UUID?
    @State private var selectedTxHash: String?
    @State private var note: String = ""
    @State private var errorMessage: String?
    @State private var showTxPicker = false

    private let accent = Color.spent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            selectionCard
            transactionCard
            footer
        }
        .padding(20)
        .frame(minWidth: 460)
        .presentationBackground(.clear)
        .sheet(isPresented: $showTxPicker) {
            TransactionPicker(
                transactions: viewModel.expenseTransactions,
                linkedHashes: viewModel.usedTransactionIDs,
                onSelect: { selectedTxHash = $0.id }
            )
            .environment(viewModel)
        }
    }

    // MARK: - Resolved selections

    private var source: Account? {
        guard let id = selectedSourceID else { return nil }
        return viewModel.reservoirSources.first { $0.id == id }
    }

    /// The linked expense snapshot (for display), when one is chosen.
    private var selectedTx: TransactionSnapshot? {
        guard let hash = selectedTxHash else { return nil }
        return viewModel.expenseTransactions.first { $0.id == hash }
    }

    /// True once a transaction is chosen.
    private var hasTransaction: Bool { selectedTxHash != nil }

    /// The expense amount to use — fixed to the linked transaction.
    private var useAmount: Double {
        selectedTx.map { abs($0.effectiveAmount) } ?? 0
    }

    /// How much the chosen reserve holds from the chosen source (the headroom),
    /// or nil until both are chosen.
    private var available: Double? {
        guard let source else { return nil }
        return amount(reserveID: reserve.id, accountID: source.id, in: viewModel.reservations)
    }

    private var isAlreadyLinked: Bool {
        guard let hash = selectedTxHash else { return false }
        return viewModel.usedTransactionIDs.contains(hash)
    }

    /// Live validation reason shown inline, once a transaction is chosen.
    private var validationMessage: String? {
        guard hasTransaction else { return nil }
        if isAlreadyLinked { return "This transaction is already used" }
        if let available, useAmount > available {
            return "Only \(available.formatted(.cad)) here (requested \(useAmount.formatted(.cad)))"
        }
        return nil
    }

    private var canSubmit: Bool {
        guard source != nil, hasTransaction,
              let available, useAmount > 0 else { return false }
        return !isAlreadyLinked && useAmount <= available
    }

    // MARK: - Cards

    // Reserve → source: using draws down the reserve's held balance.
    private var selectionCard: some View {
        HStack(spacing: 12) {
            reserveField
            arrow
            sourcePicker
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.callout.weight(.semibold))
            .foregroundStyle(accent)
    }

    // The fixed reserve this sheet was opened from.
    private var reserveField: some View {
        Text("\(reserve.emoji) \(reserve.name)")
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
    }

    private var sourcePicker: some View {
        Picker("Select Source", selection: $selectedSourceID) {
            Text("Select Source").tag(UUID?.none)
            ForEach(viewModel.reservoirSources, id: \.id) { account in
                Label(account.name, systemImage: account.type.symbol).tag(UUID?.some(account.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }

    // Transaction picker + read-only amount + headroom caption + note.
    private var transactionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            transactionField

            if let available {
                Text("\(available.formatted(.cad)) allocated here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            TextField("Add a note (optional)", text: $note)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // Tappable button that opens the expense picker.
    private var transactionField: some View {
        Button {
            showTxPicker = true
        } label: {
            HStack {
                if let details = selectedTx?.details {
                    Text(details)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                } else {
                    Text("Select transaction")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if hasTransaction {
                    Text(useAmount.formatted(.cad))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let message = errorMessage ?? validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

            Button("Use Funds", action: submit)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
        }
    }

    private func submit() {
        guard let source, let hash = selectedTxHash else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = trimmed.isEmpty ? nil : trimmed
        do {
            try viewModel.use(
                amount: useAmount, from: source, on: reserve,
                transactionContentHash: hash, note: noteValue
            )
            dismiss()
        } catch let err as ReserveError {
            errorMessage = err.userMessage
        } catch {
            errorMessage = "Something went wrong"
        }
    }
}

// MARK: - Previews

#Preview("Use Funds") {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    let reserve = Reserve(name: "Vacation", emoji: "🏖️", colorHex: "", target: 5_000, tagline: "")
    let vm = AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    )
    vm.upsertReserve(reserve)
    return ReserveUseSheet(reserve: reserve)
        .frame(width: 500)
        .padding(40)
        .environment(vm)
}
