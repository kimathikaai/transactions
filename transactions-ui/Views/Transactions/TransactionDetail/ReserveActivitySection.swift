import SwiftUI

/// The modal's Reserve section (any transaction type, when reserves exist).
/// Lists the reserve activity linked to this transaction, each with an Unlink:
/// an add/release just drops the link (the money movement stays), a use is
/// deleted (a use *is* its link). Below, a form records new linked activity:
/// Add / Release take a typed amount (never pre-filled — the link is provenance
/// only); Use draws down the full expense and is offered only for an expense
/// that isn't already used.
struct ReserveActivitySection: View {
    @Environment(AppViewModel.self) private var viewModel

    let transaction: Transaction
    @Binding var isExpanded: Bool

    enum Action: Hashable {
        case add, release, use

        init(_ type: ReserveEventType) {
            switch type {
            case .allocation: self = .add
            case .release:    self = .release
            case .use:        self = .use
            }
        }

        var label: String {
            switch self {
            case .add:     return "Add"
            case .release: return "Release"
            case .use:     return "Use"
            }
        }

        var submitLabel: String {
            switch self {
            case .add:     return "Add Funds"
            case .release: return "Release Funds"
            case .use:     return "Use"
            }
        }

        var accent: Color {
            switch self {
            case .add:     return .green
            case .release: return .orange
            case .use:     return Color.spent
            }
        }

        /// "{verb} {source}" phrase for a linked capsule.
        var verb: String {
            switch self {
            case .add:     return "Allocated from"
            case .release: return "Released into"
            case .use:     return "Used from"
            }
        }
    }

    @State private var action: Action = .add
    @State private var selectedReserveID: UUID?
    @State private var selectedSourceID: UUID?
    @State private var enteredAmount: Double = 0
    @State private var note = ""
    @State private var errorMessage: String?

    private var hash: String { transaction.contentHash }

    private var events: [ReserveEvent] {
        viewModel.reserveEvents(linkedTo: hash)
    }

    private var availableActions: [Action] {
        var actions: [Action] = [.add, .release]
        if transaction.effectiveType == .expense && !viewModel.usedTransactionIDs.contains(hash) {
            actions.append(.use)
        }
        return actions
    }

    private var defaultAction: Action {
        availableActions.contains(.use) ? .use : .add
    }

    var body: some View {
        DetailSection(
            title: "Reserve",
            descriptor: "Link this transaction to reserve activity — funds added, released, or used.",
            status: status,
            statusTint: events.isEmpty ? .neutral : .done,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(events) { event in
                    linkedCapsule(event)
                }
                form
            }
        }
        .onAppear {
            action = defaultAction
            // Convenience: auto-select the source when there's only one candidate.
            if viewModel.reservoirSources.count == 1 {
                selectedSourceID = viewModel.reservoirSources.first?.id
            }
        }
        .onChange(of: availableActions) {
            if !availableActions.contains(action) { action = defaultAction }
        }
    }

    private var status: String {
        switch events.count {
        case 0:
            return "Not linked"
        case 1 where events[0].type == .use:
            let name = viewModel.reserves.first { $0.id == events[0].reserveID }?.name
            return name.map { "Used · \($0)" } ?? "Used"
        case 1:
            return "1 activity"
        default:
            return "\(events.count) activities"
        }
    }

    // MARK: - Linked

    private func linkedCapsule(_ event: ReserveEvent) -> some View {
        let reserve = viewModel.reserves.first { $0.id == event.reserveID }
        let source = viewModel.accounts.first { $0.id == event.accountID }
        let kind = Action(event.type)
        let sign = kind == .add ? "+" : "-"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reserve.map { "\($0.emoji) \($0.name)" } ?? "(reserve no longer available)")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(kind.verb) \(source?.name ?? "—") · \(sign)\(event.amount.formatted(.cad))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // Not destructive-red: linking again is the undo.
            Button("Unlink") { unlink(event) }
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(kind.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func unlink(_ event: ReserveEvent) {
        if event.type == .use {
            viewModel.deleteReserveEvent(id: event.id)
        } else {
            viewModel.setReserveEventLink(eventID: event.id, hash: nil)
        }
    }

    // MARK: - New activity

    private var reserve: Reserve? {
        guard let selectedReserveID else { return nil }
        return viewModel.reserves.first { $0.id == selectedReserveID }
    }

    private var source: Account? {
        guard let selectedSourceID else { return nil }
        return viewModel.reservoirSources.first { $0.id == selectedSourceID }
    }

    /// Use always draws down the full expense; Add/Release use the typed amount.
    private var submitAmount: Double {
        action == .use ? abs(transaction.effectiveAmount) : enteredAmount
    }

    /// Add: the source's free balance. Release/Use: what the reserve holds from
    /// the source. Nil until both are chosen.
    private var headroom: Double? {
        guard let reserve, let source else { return nil }
        switch action {
        case .add:
            return viewModel.perSourceSummary.first { $0.account.id == source.id }?.unreserved ?? 0
        case .release, .use:
            return amount(reserveID: reserve.id, accountID: source.id, in: viewModel.reservations)
        }
    }

    private var validationMessage: String? {
        guard let headroom, submitAmount > headroom else { return nil }
        let place = action == .add ? "free" : "held there"
        return "Only \(headroom.formatted(.cad)) \(place) (needs \(submitAmount.formatted(.cad)))"
    }

    private var canSubmit: Bool {
        guard let headroom else { return false }
        return submitAmount > 0 && submitAmount <= headroom
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Action", selection: $action) {
                ForEach(availableActions, id: \.self) { action in
                    Text(action.label).tag(action)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("Reserve", selection: $selectedReserveID) {
                Text("Select Reserve").tag(UUID?.none)
                ForEach(viewModel.reserves, id: \.id) { r in
                    Text("\(r.emoji) \(r.name)").tag(UUID?.some(r.id))
                }
            }
            .pickerStyle(.menu)

            Picker("Source", selection: $selectedSourceID) {
                Text("Select Source").tag(UUID?.none)
                ForEach(viewModel.reservoirSources, id: \.id) { account in
                    Label(account.name, systemImage: account.type.symbol).tag(UUID?.some(account.id))
                }
            }
            .pickerStyle(.menu)

            if action == .use {
                if let headroom {
                    LabeledContent("Held there") {
                        Text(headroom, format: .cad).monospacedDigit()
                    }
                }
            } else {
                TextField(
                    "Amount",
                    value: Binding(
                        get: { enteredAmount == 0 ? nil : enteredAmount },
                        set: { enteredAmount = $0 ?? 0 }
                    ),
                    format: .cad
                )
                .textFieldStyle(.roundedBorder)
                if let headroom {
                    Text(action == .add
                         ? "\(headroom.formatted(.cad)) free to add"
                         : "\(headroom.formatted(.cad)) held here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                if action == .use {
                    Text("Uses \(submitAmount.formatted(.cad))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action.submitLabel, action: submit)
                    .buttonStyle(.glassProminent)
                    .tint(action.accent)
                    .disabled(!canSubmit)
            }
        }
        .font(.callout)
        .onChange(of: action) { errorMessage = nil }
        .onChange(of: selectedReserveID) { errorMessage = nil }
        .onChange(of: selectedSourceID) { errorMessage = nil }
    }

    private func submit() {
        guard let reserve, let source else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = trimmed.isEmpty ? nil : trimmed
        do {
            switch action {
            case .add:
                try viewModel.claim(amount: enteredAmount, from: source, to: reserve,
                                    note: noteValue, transactionContentHash: hash)
            case .release:
                try viewModel.release(amount: enteredAmount, from: reserve, to: source,
                                      note: noteValue, transactionContentHash: hash)
            case .use:
                try viewModel.use(amount: submitAmount, from: source, on: reserve,
                                  transactionContentHash: hash, note: noteValue)
            }
            errorMessage = nil
            note = ""
            enteredAmount = 0
            // A Use removes itself from the options; switch now rather than
            // render one frame with a selection that has no segment.
            if !availableActions.contains(action) { action = defaultAction }
        } catch let err as ReserveError {
            errorMessage = err.userMessage
        } catch {
            errorMessage = "Something went wrong"
        }
    }
}
