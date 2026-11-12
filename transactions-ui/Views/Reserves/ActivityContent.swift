import SwiftUI

/// The Reserves-page "Activity" table: one row per allocation/release/use
/// event, newest first. Mirrors `SourcesContent`'s divider-separated layout.
/// Rows highlight on hover; clicking one opens `ReserveActivityDetailSheet`,
/// where add/release links are set or cleared and "Use" events are deleted.
///
/// `compact` renders a narrow two-line row (for the Reserves page's side column):
/// the info text moves to a tooltip.
struct ActivityContent: View {
    let rows: [AppViewModel.ReserveActivityRow]
    var compact: Bool = false

    @Environment(AppViewModel.self) private var viewModel
    @State private var selection: ActivitySelection?

    var body: some View {
        list
            .sheet(item: $selection) { selection in
                ReserveActivityDetailSheet(eventID: selection.id)
                    .environment(viewModel)
            }
    }

    @ViewBuilder
    private var list: some View {
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
                        Group {
                            if compact {
                                CompactActivityRowView(row: row)
                            } else {
                                ActivityRowView(row: row)
                            }
                        }
                        .activityRowInteraction { selection = ActivitySelection(id: row.id) }
                        if index < rows.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

/// The event whose detail sheet is open.
private struct ActivitySelection: Identifiable {
    let id: UUID
}

/// Hover highlight + click target shared by both row styles. A plain-styled
/// Button (not a tap gesture) so keyboard and VoiceOver can open the row too.
private struct ActivityRowInteraction: ViewModifier {
    let onTap: () -> Void
    @State private var isHovering = false

    func body(content: Content) -> some View {
        Button {
            // The sheet covers the row, so onHover(false) may never arrive.
            isHovering = false
            onTap()
        } label: {
            content
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private extension View {
    func activityRowInteraction(onTap: @escaping () -> Void) -> some View {
        modifier(ActivityRowInteraction(onTap: onTap))
    }
}

// MARK: - Layout

private enum ActivityRowLayout {
    static let dateWidth: CGFloat = 75
    static let emojiSize: CGFloat = 20
    static let reserveWidth: CGFloat = 110
    static let actionWidth: CGFloat = 110
    static let amountWidth: CGFloat = 92
    static let spacing: CGFloat = 8
}

/// UTC-anchored short date, matching `TransactionCard`'s formatter style.
/// Shared with `ReserveActivityDetailSheet`.
let activityDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

// MARK: - Shared row presentation

/// Shared by both row styles and `ReserveActivityDetailSheet`.
extension AppViewModel.ReserveActivityRow {
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

    /// Plain-text form of the wide row's information column: the compact row's
    /// tooltip, and the wide row's tooltip (which adds the note to a link).
    var informationText: String {
        switch info {
        case .linked(let details):
            guard let note, !note.isEmpty else { return details }
            return "\(details) — \(note)"
        case .dangling:
            return "(unlinked) The linked transaction no longer resolves."
        case .note(let note):
            return note ?? ""
        }
    }
}

// MARK: - Row

private struct ActivityRowView: View {
    let row: AppViewModel.ReserveActivityRow

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
        }
        .padding(.vertical, 8)
    }

    /// Column 5. A linked row (any type) shows the transaction's details
    /// behind a link glyph — the tooltip adds the note — or "(unlinked)" when
    /// the hash no longer resolves. Unlinked rows show their optional note.
    @ViewBuilder
    private var informationView: some View {
        switch row.info {
        case .linked(let details):
            HStack(spacing: 4) {
                Image(systemName: "link")
                Text(details)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(row.informationText)
        case .dangling:
            Text("(unlinked)")
                .font(.caption.italic())
                .foregroundStyle(.secondary)
                .help("The linked transaction no longer resolves.")
        case .note(let note):
            Text(note ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(note ?? "")
        }
    }
}

// MARK: - Compact Row

/// Two-line row for narrow columns: emoji, reserve, and signed amount on top; date and
/// action phrase below. The info column becomes a tooltip.
private struct CompactActivityRowView: View {
    let row: AppViewModel.ReserveActivityRow

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
    }
}

// MARK: - Preview

/// Empty VM so row clicks have an environment to open the detail sheet from.
private func previewActivityViewModel() -> AppViewModel {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    return AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    )
}

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
    .environment(previewActivityViewModel())
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
    .environment(previewActivityViewModel())
    .frame(width: 240)
    .padding(20)
}
