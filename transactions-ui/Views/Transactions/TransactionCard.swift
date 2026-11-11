import SwiftUI

/// Shared row date formatter. Lives outside `TransactionCard` because Swift does not
/// allow static stored properties in generic types.
private let transactionCardDateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM d, yyyy"
    // Dates originate from BankCsvParser anchored at 00:00 UTC — render
    // in UTC so a 2026-06-29 CSV row displays as Jun 29 in any local TZ.
    fmt.timeZone = TimeZone(identifier: "UTC")
    return fmt
}()

/// A transaction row. The category (icon + label) is a dedicated `Button` that opens
/// the Change Category modal via `onCategoryTap` and highlights in its category color
/// on hover; a left-click on the rest of the row (date, meta) opens the edit modal via
/// `onTap`. The whole row keeps its subtle hover, and a right-click opens the shared
/// row actions as a context menu.
struct TransactionCard<Actions: View>: View {
    @Environment(AppViewModel.self) private var viewModel
    let snapshot: TransactionSnapshot
    /// Invoked on a left-click of the category region — opens the recategorize modal.
    let onCategoryTap: () -> Void
    /// Invoked on a left-click anywhere else on the row — opens the edit modal.
    let onTap: () -> Void
    /// The row's action items, shown in the right-click context menu.
    @ViewBuilder let menuActions: () -> Actions

    /// Floor for the details text, so a long note can never squeeze it out.
    private let detailsMinWidth: CGFloat = 80
    /// Cap for the notes column; it truncates beyond this. Lifted while hovering.
    private let notesMaxWidth: CGFloat = 160
    /// Cap for the details while hovering a row with notes; shorter details hug their text.
    private let detailsHoverMaxWidth: CGFloat = 240

    /// While hovering, the row shows only date, category symbol, details and notes, so
    /// the details get the freed width (still one line, so row heights stay fixed).
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                dateCell
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, 4)

            // The category opens the recategorize modal directly; hovering it lifts a
            // patch in the current category color (neutral gray when uncategorized),
            // layered over the whole-row highlight below. The padding lives inside the
            // label (ahead of contentShape) so the taller hit region includes it.
            Button(action: onCategoryTap) {
                categoryCell
                    .padding(.vertical, 6)
                    .contentShape(.rect(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .hoverHighlight(in: .rect(cornerRadius: 4), color: categoryHoverColor, opacity: 0.15)

            Button(action: onTap) {
                metaCell
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.trailing, 4)
        }
        .contentShape(.rect(cornerRadius: 6))
        .hoverHighlight(in: .rect(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .contextMenu { menuActions() }
    }

    // MARK: Cells

    private var dateCell: some View {
        Text(transactionCardDateFormatter.string(from: snapshot.date))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 80, alignment: .leading)
    }

    private var categoryCell: some View {
        HStack(spacing: 8) {
            Image(systemName: categorySymbol)
                .foregroundStyle(categoryColor)
                .frame(width: 24)

            if !isHovering {
                Text(snapshot.effectiveCategory.map { categoryLabel(category: $0, subcategory: snapshot.effectiveSubcategory) } ?? "Uncategorized")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(snapshot.effectiveCategory == nil ? .secondary : .primary)
                    .frame(width: 120, alignment: .leading)
                    .lineLimit(1)
            }
        }
    }

    private var metaCell: some View {
        HStack(spacing: 8) {
            if !isHovering {
                Text(snapshot.accountName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                    .lineLimit(1)
            }

            // Details + notes share the row's flexible space. Details always keeps at least
            // `detailsMinWidth` and fills whatever is left; notes are capped at
            // `notesMaxWidth`. Notes get first claim (higher layout priority), but SwiftUI
            // reserves details' minimum first, so a long note truncates before details do.
            // While hovering a row with notes, it flips: details hug their text up to
            // `detailsHoverMaxWidth` and claim it first, and the uncapped notes take the rest.
            if isHovering, notes != nil {
                MaxWidthLayout(maxWidth: detailsHoverMaxWidth) { detailsText }
                    .layoutPriority(1)
            } else {
                detailsText
                    .frame(minWidth: detailsMinWidth, maxWidth: .infinity, alignment: .leading)
            }

            // Edited notes, when present. A leading "|" separates the note from the
            // details, truncating with an ellipsis. Italic distinguishes it from the
            // details text; the full note is available on hover.
            if let notes {
                HStack(spacing: 6) {
                    Text("|")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(notes)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: isHovering ? nil : notesMaxWidth, alignment: .leading)
                .layoutPriority(isHovering ? 0 : 1)
                .help(notes)
            }

            if !isHovering {
                statusIcons
                    .frame(width: 30, alignment: .trailing)

                Text(formattedAmount)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                    .fixedSize()   // never compress or wrap the amount
                    .layoutPriority(2)
            }
        }
    }

    private var detailsText: some View {
        Text(snapshot.details)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(snapshot.details)
    }

    /// The edited note, or nil when absent or empty.
    private var notes: String? {
        guard let notes = snapshot.notes, !notes.isEmpty else { return nil }
        return notes
    }

    /// Quiet trailing status glyphs describing what happened to this amount:
    /// green u-turn = reimbursed, orange pencil = edited. Both render when a row
    /// is both; the fixed-width slot keeps the amount column aligned when empty.
    @ViewBuilder private var statusIcons: some View {
        HStack(spacing: 3) {
            if snapshot.isReimbursed {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(Color.income)
                    .help("Reimbursed")
                    .accessibilityLabel("Reimbursed")
            }
            if snapshot.isEdited {
                Image(systemName: "pencil")
                    .foregroundStyle(Color.orange.opacity(0.6))
                    .help("Edited")
                    .accessibilityLabel("Edited")
            }
            if snapshot.isUsed {
                Image(systemName: "cart")
                    .foregroundStyle(Color.spent)
                    .help("Used from a reserve")
                    .accessibilityLabel("Used from a reserve")
            }
        }
        .font(.caption)
    }

    private var categorySymbol: String {
        guard let id = snapshot.effectiveCategory,
              let def = viewModel.category(id: id)
        else { return "questionmark.circle.fill" }
        return def.symbol
    }

    private var categoryColor: Color {
        guard let id = snapshot.effectiveCategory,
              let def = viewModel.category(id: id)
        else { return .secondary }
        return Color(hex: def.color)
    }

    /// Tint for the category-region hover patch: the category's color when categorized,
    /// else a neutral gray (`Color.primary`) so uncategorized rows still read as tappable.
    private var categoryHoverColor: Color {
        guard let id = snapshot.effectiveCategory,
              let def = viewModel.category(id: id)
        else { return .primary }
        return Color(hex: def.color)
    }

    private func categoryLabel(category: CategoryID, subcategory: SubcategoryID?) -> String {
        let categoryName = viewModel.category(id: category)?.displayName ?? category.rawValue
        if let sub = subcategory {
            let subName = viewModel.subcategory(id: sub)?.displayName ?? sub.rawValue
            return "\(categoryName) · \(subName)"
        }
        return categoryName
    }

    private var formattedAmount: String {
        let value = abs(snapshot.effectiveAmount)
        let formatted = value.formatted(.cad)
        switch snapshot.effectiveType {
        case .expense, .transfer_out:
            return "-\(formatted)"
        case .income, .transfer_in:
            return formatted
        }
    }

    private var amountColor: Color {
        switch snapshot.effectiveType {
        case .income: .income
        case .expense: .expense
        case .transfer_in, .transfer_out: .gray
        }
    }
}

/// Proposes at most `maxWidth` to its single subview and hugs the result. Unlike
/// `.frame(maxWidth:)`, which grows to fill its cap, short content stays short.
private struct MaxWidthLayout: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? .infinity, maxWidth), height: proposal.height)
    }
}
