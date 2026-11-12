import SwiftUI

/// Opened by clicking an Activity row. A read-only summary of one ledger event
/// plus its linked transaction. Allocation/release events can link or unlink a
/// transaction (provenance only — saved immediately); a "Use" event shows its
/// expense and is deleted from here. Styled after `ReserveUseSheet`.
struct ReserveActivityDetailSheet: View {
    let eventID: UUID

    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showTxPicker = false
    @State private var confirmingDelete = false

    /// Re-read live after every write; nil once the event is gone.
    private var row: AppViewModel.ReserveActivityRow? {
        viewModel.reserveActivity.first { $0.id == eventID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let row {
                summaryCard(row)
                linkCard(row)
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 460)
        .presentationBackground(.clear)
        .onAppear { viewModel.lastSaveError = nil }
        .onChange(of: row == nil) { _, isGone in
            if isGone { dismiss() }
        }
        .sheet(isPresented: $showTxPicker) {
            TransactionPicker(
                transactions: viewModel.transactionsByDateDesc,
                linkedHashes: [],
                onSelect: { viewModel.setReserveEventLink(eventID: eventID, hash: $0.id) }
            )
            .environment(viewModel)
        }
    }

    // MARK: - Cards

    private func summaryCard(_ row: AppViewModel.ReserveActivityRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ReserveEmojiChip(emoji: row.reserveEmoji, size: 20)
                Text(row.reserveName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(row.signedAmount)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(row.accent)
            }
            HStack(spacing: 4) {
                Text(activityDateFormatter.string(from: row.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                row.actionView
            }
            if let note = row.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func linkCard(_ row: AppViewModel.ReserveActivityRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Linked transaction")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                linkedDescription(row)
                Spacer(minLength: 8)
                linkAction(row)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    @ViewBuilder
    private func linkedDescription(_ row: AppViewModel.ReserveActivityRow) -> some View {
        switch row.info {
        case .linked(let details):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                    Text(details)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.callout)
                if let date = row.linkedDate {
                    Text(activityDateFormatter.string(from: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .dangling:
            Text("(unlinked)")
                .font(.callout.italic())
                .foregroundStyle(.secondary)
                .help("The linked transaction no longer resolves.")
        case .note:
            Text("None")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Use: delete the event (a use *is* its link). Add/release: link or unlink.
    @ViewBuilder
    private func linkAction(_ row: AppViewModel.ReserveActivityRow) -> some View {
        if row.type == .use {
            Button("Delete Activity", role: .destructive) { confirmingDelete = true }
                .buttonStyle(.glass)
                .confirmationDialog(
                    "Delete this activity?",
                    isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    // The sheet dismisses itself once the row is gone (see body).
                    Button("Delete", role: .destructive) {
                        viewModel.deleteReserveEvent(id: row.id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the ledger event and recomputes reserve balances. This cannot be undone.")
                }
        } else if row.transactionContentHash != nil {
            Button("Unlink") {
                viewModel.setReserveEventLink(eventID: row.id, hash: nil)
            }
            .buttonStyle(.glass)
        } else {
            Button("Link Transaction…") { showTxPicker = true }
                .buttonStyle(.glass)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.regularMaterial)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = viewModel.lastSaveError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            Button("Done") { dismiss() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Previews

#Preview("Allocation") {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    let reserve = Reserve(name: "Tithe", emoji: "🙏", colorHex: "", target: 5_000, tagline: "")
    let allocation = ReserveEvent(reserveID: reserve.id, accountID: UUID(), type: .allocation,
                                  amount: 300, note: "payday")
    let eventStore = ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json"))
    try? eventStore.append(allocation)
    let vm = AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: eventStore,
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    )
    vm.upsertReserve(reserve)
    return ReserveActivityDetailSheet(eventID: allocation.id)
        .frame(width: 500)
        .padding(40)
        .environment(vm)
}
