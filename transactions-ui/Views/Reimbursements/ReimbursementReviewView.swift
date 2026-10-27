import SwiftUI

/// US10 — the one place to review and undo every reimbursement link, newest
/// first. A flat, static table (no controls): `Date · Expense · Source ·
/// Amount · [unlink]`. Mirrors `ActivityContent`'s divider-separated layout.
///
/// Embedded as the Transactions page's "Reimbursements" tab (the enclosing
/// `SectionTab`/`TabbedSection` supplies the card chrome and title), so this
/// view renders only the table body — no `SectionContainer` of its own.
///
/// Read-only overlay: unlinking returns the snapshot amount to the source's
/// pool and frees the expense to be linked again (via
/// `AppViewModel.unlinkReimbursement(expenseHash:)`). A dangling link (its
/// expense or source hash no longer resolves, US13) still renders in place —
/// the unresolved cell reads "(… no longer available)" — and stays unlinkable.
struct ReimbursementReviewView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        let rows = viewModel.reimbursementReview
        if rows.isEmpty {
            Text("No reimbursements yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 0) {
                ReimbursementHeaderRow()
                Divider().padding(.bottom,4)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(rows) { row in
                            ReimbursementRowView(
                                row: row,
                                onUnlink: { viewModel.unlinkReimbursement(expenseHash: row.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Layout

private enum ReimbursementRowLayout {
    static let dateWidth: CGFloat = 92
    static let sourceWidth: CGFloat = 170
    static let amountWidth: CGFloat = 92
    static let unlinkWidth: CGFloat = 20
    static let spacing: CGFloat = 8
}

/// UTC-anchored short date, matching `TransactionCard`/`ActivityContent`.
private let reimbursementDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

// MARK: - Header

private struct ReimbursementHeaderRow: View {
    var body: some View {
        HStack(spacing: ReimbursementRowLayout.spacing) {
            header("Date")
                .frame(width: ReimbursementRowLayout.dateWidth, alignment: .leading)
            header("Expense")
                .frame(maxWidth: .infinity, alignment: .leading)
            header("Source")
                .frame(width: ReimbursementRowLayout.sourceWidth, alignment: .leading)
            header("Amount")
                .frame(width: ReimbursementRowLayout.amountWidth, alignment: .trailing)
            // Empty slot over the unlink column keeps the header aligned.
            Color.clear.frame(width: ReimbursementRowLayout.unlinkWidth, height: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Row

private struct ReimbursementRowView: View {
    let row: AppViewModel.ReimbursementReviewRow
    var onUnlink: () -> Void

    @State private var confirmingUnlink = false
    @State private var isHoveringTrash = false

    /// Expense details with its account folded in; nil when the expense hash no
    /// longer resolves to a live transaction (US13).
    private var expenseText: String? {
        guard let details = row.expenseDetails else { return nil }
        if let account = row.expenseAccountName {
            return "\(details) · \(account)"
        }
        return details
    }

    /// Source income details with its short date; nil when the source hash no
    /// longer resolves (US13).
    private var sourceText: String? {
        guard let details = row.sourceDetails else { return nil }
        if let date = row.sourceDate {
            return "\(details) · \(reimbursementDateFormatter.string(from: date))"
        }
        return details
    }

    var body: some View {
        HStack(spacing: ReimbursementRowLayout.spacing) {
            Text(reimbursementDateFormatter.string(from: row.linkedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: ReimbursementRowLayout.dateWidth, alignment: .leading)

            cell(text: expenseText, missing: "(expense no longer available)")
                .frame(maxWidth: .infinity, alignment: .leading)

            cell(text: sourceText, missing: "(source no longer available)")
                .frame(width: ReimbursementRowLayout.sourceWidth, alignment: .leading)

            Text(row.amount.formatted(.cad))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.income)
                .lineLimit(1)
                .frame(width: ReimbursementRowLayout.amountWidth, alignment: .trailing)

            Button {
                confirmingUnlink = true
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(isHoveringTrash ? Color.red : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: ReimbursementRowLayout.unlinkWidth, alignment: .trailing)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHoveringTrash = hovering }
            }
            .help("Unlink this expense")
            .confirmationDialog(
                "Unlink this expense?",
                isPresented: $confirmingUnlink,
                titleVisibility: .visible
            ) {
                Button("Unlink", role: .destructive, action: onUnlink)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The reimbursed amount returns to the source's pool and this expense becomes available to link again.")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
//        .hoverHighlight(in: .rect(cornerRadius: 6))
    }

    /// A truncated text cell with a full-text tooltip, or the italic-secondary
    /// dangling fallback when the underlying transaction no longer resolves.
    @ViewBuilder
    private func cell(text: String?, missing: String) -> some View {
        if let text {
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(text)
        } else {
            Text(missing)
                .font(.caption.italic())
                .foregroundStyle(.secondary)
                .help("The linked transaction no longer resolves.")
        }
    }
}

// MARK: - Preview

#Preview("Reimbursements") {
    let rows: [AppViewModel.ReimbursementReviewRow] = [
        .init(id: "a", linkedAt: Date(timeIntervalSince1970: 1_723_000_000),
              expenseDetails: "AIR CANADA FLIGHT", expenseAccountName: "Travel Rewards Card",
              sourceDetails: "WORK TRAVEL PAYOUT",
              sourceDate: Date(timeIntervalSince1970: 1_722_900_000), amount: 450),
        .init(id: "b", linkedAt: Date(timeIntervalSince1970: 1_722_800_000),
              expenseDetails: "TEAM DINNER", expenseAccountName: "Travel Rewards Card",
              sourceDetails: "WORK TRAVEL PAYOUT",
              sourceDate: Date(timeIntervalSince1970: 1_722_900_000), amount: 120),
        .init(id: "c", linkedAt: Date(timeIntervalSince1970: 1_722_500_000),
              expenseDetails: nil, expenseAccountName: nil,
              sourceDetails: "Q3 EXPENSE REIMBURSE",
              sourceDate: Date(timeIntervalSince1970: 1_722_400_000), amount: 80),
    ]
    // Note: preview uses static rows; the live view reads viewModel.reimbursementReview.
    ReimbursementReviewViewPreviewHarness(rows: rows)
        .frame(width: 720)
        .padding(20)
}

/// Renders the table body against fixed rows, bypassing the environment VM, so
/// the layout can be previewed without seeding an AppViewModel.
private struct ReimbursementReviewViewPreviewHarness: View {
    let rows: [AppViewModel.ReimbursementReviewRow]
    var body: some View {
        SectionContainer(title: "Links") {
            VStack(spacing: 0) {
                ReimbursementHeaderRow()
                Divider()
                LazyVStack(spacing: 4) {
                    ForEach(rows) { row in
                        ReimbursementRowView(row: row, onUnlink: {})
                    }
                }
            }
        }
    }
}
