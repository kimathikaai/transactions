import SwiftUI

/// A quick-action popup for moving money between a source account and a reserve.
/// Styled after `ReserveEditSheet`. `Mode` decides the flow direction (which the
/// arrow points along), the labels, and which side of the arrow each picker sits on:
///   - `.allocate`  →  [Source] → [Reserve]   (money into the reserve)
///   - `.release`   →  [Reserve] → [Source]   (money back out to the source)
/// The reserve is fixed (the card that opened the sheet); only the source is picked.
/// A transaction may optionally be linked as provenance (e.g. the paycheque behind
/// an add); it never sets or limits the amount.
struct ReserveTransferSheet: View {
    enum Mode {
        case allocate, release

        var actionLabel: String { self == .allocate ? "Add Funds" : "Release Funds" }
        var amountPlaceholder: String { self == .allocate ? "Amount to add" : "Amount to release" }
        var accent: Color { self == .allocate ? .green : .orange }
    }

    let mode: Mode
    let reserve: Reserve

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // Selection is tracked by id so the picker doesn't require `Account`
    // to be Hashable and never holds a stale value copy.
    @State private var selectedSourceID: UUID?
    @State private var transferAmount: Double = 0
    @State private var errorMessage: String?
    @State private var note: String = ""
    @State private var linkedTxHash: String?
    @State private var showTxPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            selectionCard
            amountCard
            footer
        }
        .padding(20)
        .frame(minWidth: 460)
        .presentationBackground(.clear)
        .sheet(isPresented: $showTxPicker) {
            TransactionPicker(
                transactions: viewModel.transactionsByDateDesc,
                linkedHashes: [],
                onSelect: { linkedTxHash = $0.id }
            )
            .environment(viewModel)
        }
    }

    // MARK: - Resolved selections

    private var source: Account? {
        guard let id = selectedSourceID else { return nil }
        return viewModel.reservoirSources.first { $0.id == id }
    }

    /// The headroom for the current selection, or nil until enough is chosen:
    ///   - allocate: the source's unreserved (free) balance.
    ///   - release: how much *this* reserve holds *from this* source.
    private var available: Double? {
        switch mode {
        case .allocate:
            guard let source else { return nil }
            return viewModel.perSourceSummary.first { $0.account.id == source.id }?.unreserved ?? 0
        case .release:
            guard let source else { return nil }
            return amount(reserveID: reserve.id, accountID: source.id, in: viewModel.reservations)
        }
    }

    private var canSubmit: Bool {
        guard source != nil, let available, transferAmount > 0 else { return false }
        return transferAmount <= available
    }

    // MARK: - Cards

    // Reserve label + source picker, ordered by flow direction with a tinted arrow.
    private var selectionCard: some View {
        HStack(spacing: 12) {
            if mode == .allocate {
                sourcePicker
                arrow
                reserveLabel
            } else {
                reserveLabel
                arrow
                sourcePicker
            }
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
            .foregroundStyle(mode.accent)
    }

    // The fixed target reserve (the card that opened this sheet).
    private var reserveLabel: some View {
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

    // Amount field (CAD) + available-headroom caption, mirroring the target card.
    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                mode.amountPlaceholder,
                value: Binding(
                    get: { transferAmount == 0 ? nil : transferAmount },
                    set: { transferAmount = $0 ?? 0 }
                ),
                format: .cad
            )
            .textFieldStyle(.plain)
            .font(.callout)

            if let available {
                Text(availabilityCaption(available))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            TextField("Add a note (optional)", text: $note)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()
            transactionField
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    /// The optionally linked transaction (for display), when one is chosen.
    private var linkedTx: TransactionSnapshot? {
        guard let hash = linkedTxHash else { return nil }
        return viewModel.transactionsByDateDesc.first { $0.id == hash }
    }

    // Tappable row that opens the transaction picker; × clears the link.
    private var transactionField: some View {
        HStack {
            Button {
                showTxPicker = true
            } label: {
                HStack {
                    if let tx = linkedTx {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        Text(tx.details)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(tx.signedAmountText)
                            .monospacedDigit()
                            .foregroundStyle(tx.amountTint)
                    } else {
                        Text("Link a transaction (optional)")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if linkedTx != nil {
                Button {
                    linkedTxHash = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove the linked transaction")
            }
        }
        .font(.callout)
    }

    private func availabilityCaption(_ available: Double) -> String {
        switch mode {
        case .allocate: return "\(available.formatted(.cad)) free to add"
        case .release:  return "\(available.formatted(.cad)) allocated here"
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

            Button(mode.actionLabel, action: submit)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
        }
    }

    private func submit() {
        guard let source else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = trimmed.isEmpty ? nil : trimmed
        do {
            switch mode {
            case .allocate:
                try viewModel.claim(amount: transferAmount, from: source, to: reserve, note: noteValue,
                                    transactionContentHash: linkedTxHash)
            case .release:
                try viewModel.release(amount: transferAmount, from: reserve, to: source, note: noteValue,
                                      transactionContentHash: linkedTxHash)
            }
            dismiss()
        } catch let err as ReserveError {
            errorMessage = err.userMessage
        } catch {
            errorMessage = "Something went wrong"
        }
    }
}

// MARK: - Previews

private let previewReserve = Reserve(name: "Vacation", emoji: "🏖️", colorHex: "", target: 5_000, tagline: "")

private func previewViewModel() -> AppViewModel {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    let vm = AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    )
    vm.upsertReserve(previewReserve)
    vm.upsertReserve(Reserve(name: "New Bike", emoji: "🚲", colorHex: "", target: 850, tagline: ""))
    return vm
}

#Preview("Add Funds") {
    ReserveTransferSheet(mode: .allocate, reserve: previewReserve)
        .frame(width: 500)
        .padding(40)
        .environment(previewViewModel())
}

#Preview("Release Funds") {
    ReserveTransferSheet(mode: .release, reserve: previewReserve)
        .frame(width: 500)
        .padding(40)
        .environment(previewViewModel())
}
