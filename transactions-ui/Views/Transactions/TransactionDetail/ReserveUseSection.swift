import SwiftUI

/// The modal's Reserve section (expenses only, when reserves exist). Not used:
/// pick the reserve and the source account it was saved in, then press Use —
/// picking alone changes nothing, because a use draws down held money. Used: the
/// reserve and source with an Unlink that applies at once. The amount is always
/// the full expense.
struct ReserveUseSection: View {
    @Environment(AppViewModel.self) private var viewModel

    let expense: Transaction
    @Binding var isExpanded: Bool

    @State private var selectedReserveID: UUID?
    @State private var selectedSourceID: UUID?
    @State private var note = ""
    @State private var errorMessage: String?

    private var event: ReserveEvent? {
        viewModel.usageEvent(forExpense: expense.contentHash)
    }

    var body: some View {
        DetailSection(
            title: "Reserve",
            descriptor: "Did you pay for this with money saved in a reserve? Linking it draws down that reserve.",
            status: status,
            statusTint: event == nil ? .neutral : .done,
            isExpanded: $isExpanded
        ) {
            if let event {
                usedCapsule(event)
            } else {
                picker
            }
        }
        .onAppear {
            // Convenience: auto-select the source when there's only one candidate.
            if viewModel.reservoirSources.count == 1 {
                selectedSourceID = viewModel.reservoirSources.first?.id
            }
        }
    }

    private var status: String {
        guard let event else { return "Not used" }
        let name = viewModel.reserves.first { $0.id == event.reserveID }?.name
        return name.map { "Used · \($0)" } ?? "Used"
    }

    // MARK: - Used

    private func usedCapsule(_ event: ReserveEvent) -> some View {
        let reserve = viewModel.reserves.first { $0.id == event.reserveID }
        let source = viewModel.accounts.first { $0.id == event.accountID }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reserve.map { "\($0.emoji) \($0.name)" } ?? "(reserve no longer available)")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text([source.map { "from \($0.name)" }, "used \(event.amount.formatted(.cad))"]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // Not destructive-red: using again is the undo.
            Button("Unlink") {
                viewModel.deleteReserveEvent(id: event.id)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.spent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Not used

    private var useAmount: Double { abs(expense.effectiveAmount) }

    private var reserve: Reserve? {
        guard let selectedReserveID else { return nil }
        return viewModel.reserves.first { $0.id == selectedReserveID }
    }

    private var source: Account? {
        guard let selectedSourceID else { return nil }
        return viewModel.reservoirSources.first { $0.id == selectedSourceID }
    }

    /// How much the chosen reserve holds from the chosen source (the headroom).
    private var available: Double? {
        guard let reserve, let source else { return nil }
        return amount(reserveID: reserve.id, accountID: source.id, in: viewModel.reservations)
    }

    private var validationMessage: String? {
        guard let available, useAmount > available else { return nil }
        return "Only \(available.formatted(.cad)) held there (needs \(useAmount.formatted(.cad)))"
    }

    private var canUse: Bool {
        guard let available else { return false }
        return useAmount > 0 && useAmount <= available
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Reserve", selection: $selectedReserveID) {
                Text("Select Reserve").tag(UUID?.none)
                ForEach(viewModel.reserves, id: \.id) { r in
                    Text("\(r.emoji) \(r.name)").tag(UUID?.some(r.id))
                }
            }
            .pickerStyle(.menu)

            Picker("From source", selection: $selectedSourceID) {
                Text("Select Source").tag(UUID?.none)
                ForEach(viewModel.reservoirSources, id: \.id) { account in
                    Label(account.name, systemImage: account.type.symbol).tag(UUID?.some(account.id))
                }
            }
            .pickerStyle(.menu)

            if let available {
                LabeledContent("Held there") {
                    Text(available, format: .cad).monospacedDigit()
                }
            }

            TextField("Activity note (optional)", text: $note)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                if let message = errorMessage ?? validationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 0)
                Text("Uses \(useAmount.formatted(.cad))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Use", action: useFunds)
                    .buttonStyle(.glassProminent)
                    .tint(Color.spent)
                    .disabled(!canUse)
            }
        }
        .font(.callout)
        .onChange(of: selectedReserveID) { errorMessage = nil }
        .onChange(of: selectedSourceID) { errorMessage = nil }
    }

    private func useFunds() {
        guard let reserve, let source else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try viewModel.use(
                amount: useAmount, from: source, on: reserve,
                transactionContentHash: expense.contentHash,
                note: trimmed.isEmpty ? nil : trimmed
            )
            errorMessage = nil
            note = ""
        } catch let err as ReserveError {
            errorMessage = err.userMessage
        } catch {
            errorMessage = "Something went wrong"
        }
    }
}
