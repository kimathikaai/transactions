import SwiftUI

/// The modal's Links section (every type): the transaction's links — transfer
/// auto-pairs and manual links — each with Open, Keep (auto-pairs only) and
/// Unlink, all applying at once. Below them, link to an existing transaction or
/// create the counterpart and link it.
struct LinksSection: View {
    @Environment(AppViewModel.self) private var viewModel

    let transaction: Transaction
    @Binding var isExpanded: Bool
    /// Re-targets the modal at the given counterpart hash.
    let onOpen: (String) -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        // CSV dates are anchored at 00:00 UTC — render in UTC (see TransactionCard).
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var links: [AppViewModel.ResolvedLink] {
        viewModel.links(for: transaction.contentHash)
    }

    var body: some View {
        DetailSection(
            title: "Links",
            descriptor: "Connect this to related transactions, like the other side of a transfer.",
            status: status,
            statusTint: links.contains(where: \.isLive) ? .done : .neutral,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !links.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(links) { link in
                            capsule(link)
                        }
                    }
                }
                LinkCandidatePicker(source: transaction)
                Divider()
                CreateLinkedTransactionForm(source: transaction)
            }
        }
    }

    private var status: String {
        let live = links.filter(\.isLive)
        guard let only = live.first else { return "Not linked" }
        guard live.count == 1 else { return "\(live.count) links" }
        let account = counterpartAccountName(only) ?? "—"
        return only.origin == .auto ? "Auto · \(account)" : "Linked · \(account)"
    }

    private func counterpartAccountName(_ link: AppViewModel.ResolvedLink) -> String? {
        viewModel.transaction(withHash: link.counterpartHash)
            .flatMap { viewModel.account(id: $0.accountID)?.name }
    }

    // MARK: - Existing links

    private func capsule(_ link: AppViewModel.ResolvedLink) -> some View {
        let counterpart = link.isLive ? viewModel.transaction(withHash: link.counterpartHash) : nil
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let counterpart {
                    HStack(spacing: 6) {
                        Text(counterpart.details)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(counterpart.details)
                        badge(link.kind == .transfer ? "Transfer" : "Related")
                        badge(link.origin == .auto ? "Auto" : "Manual")
                    }
                    Text(subtitle(counterpart))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("(counterpart no longer available)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let note = link.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let counterpart {
                Text(counterpart.effectiveAmount, format: .cad)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(amountTint(counterpart))
            }
            buttons(link, isLive: counterpart != nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            (counterpart == nil ? Color.secondary : Color.income).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func buttons(_ link: AppViewModel.ResolvedLink, isLive: Bool) -> some View {
        HStack(spacing: 6) {
            if isLive {
                Button("Open") { onOpen(link.counterpartHash) }
            }
            if link.origin == .auto, let counterpart = viewModel.transaction(withHash: link.counterpartHash) {
                Button("Keep") { viewModel.linkTransactions(transaction, counterpart) }
                    .help("Save this automatic match so it can't change on a later load")
            }
            // Not destructive-red: re-linking is the undo.
            Button("Unlink") { viewModel.unlink(link) }
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    private func subtitle(_ counterpart: Transaction) -> String {
        let account = viewModel.account(id: counterpart.accountID)?.name ?? "—"
        return "\(account) · \(Self.dateFormatter.string(from: counterpart.date))"
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(.secondary)
            .background(.secondary.opacity(0.12), in: Capsule())
    }

    private func amountTint(_ tx: Transaction) -> Color {
        switch tx.effectiveType {
        case .expense, .transfer_out: return .expense
        case .income, .transfer_in:   return .income
        }
    }
}
