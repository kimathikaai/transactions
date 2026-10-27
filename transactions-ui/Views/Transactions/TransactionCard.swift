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
/// on hover; the rest of the row (date, meta) is split into two `Menu`s presenting the
/// shared row actions, and the whole row keeps its subtle hover + right-click context
/// menu. The category must live *outside* any `Menu` because a sub-tap inside a
/// `.menuStyle(.button)` label does not fire reliably.
struct TransactionCard<Actions: View>: View {
    @Environment(AppViewModel.self) private var viewModel
    let snapshot: TransactionSnapshot
    /// Invoked on a left-click of the category region — opens the recategorize modal.
    let onCategoryTap: () -> Void
    /// The row's action items, shared by both flanking menus and the context menu.
    @ViewBuilder let menuActions: () -> Actions

    var body: some View {
        HStack(spacing: 8) {
            Menu { menuActions() } label: {
                dateCell
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
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

            Menu { menuActions() } label: {
                metaCell
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity)
                .padding(.trailing, 4)
        }
        .contentShape(.rect(cornerRadius: 6))
        .hoverHighlight(in: .rect(cornerRadius: 6))
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

            Text(snapshot.effectiveCategory.map { categoryLabel(category: $0, subcategory: snapshot.effectiveSubcategory) } ?? "Uncategorized")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(snapshot.effectiveCategory == nil ? .secondary : .primary)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
        }
    }

    private var metaCell: some View {
        HStack(spacing: 8) {
            Text(snapshot.accountName ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)

            Text(snapshot.details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Edited notes, when present. A leading "|" separates the note from
            // the details; fixed-width so it never crowds out the details or amount,
            // truncating with an ellipsis. Italic distinguishes it from the details
            // text; the full note is available on hover.
            if let notes = snapshot.notes, !notes.isEmpty {
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
                .frame(width: 160, alignment: .leading)
                .help(notes)
            }

            Spacer()

            statusIcons
                .frame(width: 30, alignment: .trailing)

            Text(formattedAmount)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(amountColor)
        }
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
