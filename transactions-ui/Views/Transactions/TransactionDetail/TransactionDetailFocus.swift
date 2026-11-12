import Foundation

/// Which row action opened the transaction modal — decides the expanded section.
enum TransactionDetailFocus {
    case edit           // plain Edit: expand whatever needs attention
    case category
    case reimbursement
    case reserve
    case links
}

/// The modal's collapsible sections (the original-transaction card is always shown).
enum TransactionDetailSection: Hashable {
    case category
    case notes
    case reimbursement
    case reserve
    case links

    /// The chosen action's section alone; for plain Edit, the sections that need
    /// attention (Category when uncategorized, Links for a transfer with no live
    /// link) or already hold something.
    static func initialExpansion(
        focus: TransactionDetailFocus,
        isUncategorized: Bool,
        hasNotes: Bool,
        isReimbursed: Bool,
        hasReserveActivity: Bool,
        isUnlinkedTransfer: Bool = false,
        hasLinks: Bool = false
    ) -> Set<TransactionDetailSection> {
        switch focus {
        case .category:      return [.category]
        case .reimbursement: return [.reimbursement]
        case .reserve:       return [.reserve]
        case .links:         return [.links]
        case .edit:
            var sections: Set<TransactionDetailSection> = []
            if isUncategorized { sections.insert(.category) }
            if hasNotes { sections.insert(.notes) }
            if isReimbursed { sections.insert(.reimbursement) }
            if hasReserveActivity { sections.insert(.reserve) }
            if isUnlinkedTransfer || hasLinks { sections.insert(.links) }
            return sections
        }
    }
}

/// Presents the modal for one transaction. Carries the hash (not the value) so
/// the modal can re-read live state after every write; `fallback` covers a
/// transaction that isn't in `allTransactions`.
struct TransactionDetailRequest: Identifiable {
    let fallback: Transaction
    let focus: TransactionDetailFocus
    var hash: String { fallback.contentHash }
    var id: String { hash }
}
