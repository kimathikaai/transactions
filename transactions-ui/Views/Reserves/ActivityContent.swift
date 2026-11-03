import SwiftUI

/// The Reserves-page "Activity" table: one row per allocation/release/use
/// event, newest first. Mirrors `SourcesContent`'s divider-separated layout.
/// Only "Use" rows can be deleted (hard-removing the underlying ledger event)
/// via a trailing affordance guarded by a destructive confirmation; allocation
/// and release rows show no delete affordance.
///
/// `compact` renders a narrow two-line row (for the Reserves page's side column):
/// the info text moves to a tooltip and "Use" deletion to the right-click menu.
struct ActivityContent: View {
    let rows: [AppViewModel.ReserveActivityRow]
    var onDelete: (UUID) -> Void = { _ in }
    var compact: Bool = false

    var body: some View {
        if rows.isEmpty {
            Text("No allocations, releases, or uses yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if compact {
                            CompactActivityRowView(row: row, onDelete: { onDelete(row.id) })
                        } else {
                            ActivityRowView(row: row, onDelete: { onDelete(row.id) })
                        }
                        if index < rows.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Layout

private enum ActivityRowLayout {
    static let dateWidth: CGFloat = 75
    static let emojiSize: CGFloat = 20
    static let reserveWidth: CGFloat = 110
    static let actionWidth: CGFloat = 110
    static let amountWidth: CGFloat = 92
    static let deleteWidth: CGFloat = 20
    static let spacing: CGFloat = 8
}

/// UTC-anchored short date, matching `TransactionCard`'s formatter style.
private let activityDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

// MARK: - Shared row presentation

private extension AppViewModel.ReserveActivityRow {
    var accent: Color {
        switch type {
        case .allocation: return .secondary
        case .release:    return .orange
        case .use:        return .spent
        }
    }

    /// The action phrase folds the event type and its source account into one
    /// sentence: the verb carries the type accent, the "from/into {source}"
    /// remainder stays neutral. Money enters the reserve *from* an account
    /// (allocate/use) and returns *into* an account (release).
    var actionView: some View {
        let verb: String
        let preposition: String
        switch type {
        case .allocation: verb = "Allocated"; preposition = "from"
        case .release:    verb = "Released";  preposition = "into"
        case .use:        verb = "Used";      preposition = "from"
        }
        return HStack(spacing: 0) {
            Text(verb).foregroundStyle(accent)
            Text(" \(preposition) \(sourceName)").foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// Positive for allocations (money in); negative for releases and uses
    /// (money leaving the reserve).
    var signedAmount: String {
        let sign = type == .allocation ? "+" : "-"
        return "\(sign)\(amount.formatted(.cad))"
    }

    /// Plain-text form of the wide row's information column, for the compact row's tooltip.
    var informationText: String {
        if type == .use {
            return linkedDetails ?? "(unlinked) The linked transaction no longer resolves."
        }
        return note ?? ""
    }
}

/// Destructive confirmation shared by both row styles before hard-removing a "Use" event.
private extension View {
    func deleteActivityConfirmation(isPresented: Binding<Bool>, onDelete: @escaping () -> Void) -> some View {
        confirmationDialog(
            "Delete this activity?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the ledger event and recomputes reserve balances. This cannot be undone.")
        }
    }
}

// MARK: - Row

private struct ActivityRowView: View {
    let row: AppViewModel.ReserveActivityRow
    var onDelete: () -> Void

    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: ActivityRowLayout.spacing) {
            Text(activityDateFormatter.string(from: row.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: ActivityRowLayout.dateWidth, alignment: .leading)

            ReserveEmojiChip(emoji: row.reserveEmoji, size: ActivityRowLayout.emojiSize)

            Text(row.reserveName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: ActivityRowLayout.reserveWidth, alignment: .leading)

            row.actionView
                .frame(width: ActivityRowLayout.actionWidth, alignment: .leading)

            informationView
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.signedAmount)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(row.accent)
                .lineLimit(1)
                .frame(width: ActivityRowLayout.amountWidth, alignment: .trailing)

            // Only "Use" events are deletable. Deleting an allocation or release
            // would corrupt the folded balance (a later offsetting event would
            // still subtract against nothing), so those rows show no affordance —
            // an empty spacer keeps the columns aligned.
            if row.type == .use {
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: ActivityRowLayout.deleteWidth, alignment: .trailing)
                .help("Delete this activity")
                .deleteActivityConfirmation(isPresented: $confirmingDelete, onDelete: onDelete)
            } else {
                Color.clear
                    .frame(width: ActivityRowLayout.deleteWidth, height: 0)
            }
        }
        .padding(.vertical, 8)
    }

    /// Column 5. Use rows carry a linked expense transaction: show its
    /// details behind a link glyph, or "(unlinked)" when the hash no longer
    /// resolves. Allocate/release rows show their optional note instead.
    @ViewBuilder
    private var informationView: some View {
        if row.type == .use {
            if let details = row.linkedDetails {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text(details)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(details)
            } else {
                Text("(unlinked)")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
                    .help("The linked transaction no longer resolves.")
            }
        } else {
            Text(row.note ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(row.note ?? "")
        }
    }
}

// MARK: - Compact Row

/// Two-line row for narrow columns: emoji, reserve, and signed amount on top; date and
/// action phrase below. The info column becomes a tooltip; "Use" rows are deleted via
/// the right-click menu.
private struct CompactActivityRowView: View {
    let row: AppViewModel.ReserveActivityRow
    var onDelete: () -> Void

    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: ActivityRowLayout.spacing) {
                ReserveEmojiChip(emoji: row.reserveEmoji, size: ActivityRowLayout.emojiSize)

                Text(row.reserveName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text(row.signedAmount)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(row.accent)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Text(activityDateFormatter.string(from: row.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                row.actionView
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(row.informationText)
        .contextMenu {
            if row.type == .use {
                Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .deleteActivityConfirmation(isPresented: $confirmingDelete, onDelete: onDelete)
    }
}

// MARK: - Preview

#Preview("Activity") {
    let vacationID = UUID()
    let emergencyID = UUID()
    let rows: [AppViewModel.ReserveActivityRow] = [
        .init(id: UUID(), date: Date(timeIntervalSince1970: 1_722_600_000),
              reserveID: vacationID,
              reserveEmoji: "🏖️", reserveName: "Vacation", sourceName: "Savings",
              type: .allocation, amount: 300, note: "summer trip fund",
              transactionContentHash: nil, linkedDetails: nil, linkedDate: nil),
        .init(id: UUID(), date: Date(timeIntervalSince1970: 1_722_300_000),
              reserveID: vacationID,
              reserveEmoji: "🏖️", reserveName: "Vacation", sourceName: "Savings",
              type: .use, amount: 180, note: nil,
              transactionContentHash: "abc123",
              linkedDetails: "AIR CANADA FLIGHT",
              linkedDate: Date(timeIntervalSince1970: 1_722_200_000)),
        .init(id: UUID(), date: Date(timeIntervalSince1970: 1_722_000_000),
              reserveID: emergencyID,
              reserveEmoji: "🚨", reserveName: "Emergency", sourceName: "Chequing",
              type: .release, amount: 120, note: "car repair",
              transactionContentHash: nil, linkedDetails: nil, linkedDate: nil),
    ]
    SectionContainer(title: "Activity") {
        ActivityContent(rows: rows)
    }
    .frame(width: 860)
    .padding(20)
}

#Preview("Activity (compact)") {
    let rows: [AppViewModel.ReserveActivityRow] = [
        .init(id: UUID(), date: Date(timeIntervalSince1970: 1_722_600_000),
              reserveID: UUID(),
              reserveEmoji: "🏖️", reserveName: "Vacation", sourceName: "Savings",
              type: .allocation, amount: 300, note: "summer trip fund",
              transactionContentHash: nil, linkedDetails: nil, linkedDate: nil),
    ]
    SectionContainer(title: "Activity") {
        ActivityContent(rows: rows, compact: true)
    }
    .frame(width: 240)
    .padding(20)
}
