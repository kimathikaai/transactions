import Foundation

enum TransactionType: String, CaseIterable, Identifiable, Comparable, Codable, Sendable {
    case expense
    case income
    case transfer_in
    case transfer_out

    var id: String { rawValue }

    var displayName: String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    static func < (lhs: TransactionType, rhs: TransactionType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Value-type transaction. Not persisted directly — every launch, the
/// `AppViewModel` rebuilds `[Transaction]` from the per-account CSVs via
/// `BankCsvParser` + `ImportPipeline`. User edits live in `edits.json`
/// keyed by `contentHash` and are stitched onto each transaction at load
/// time (`edit` property below).
struct Transaction: Identifiable, Equatable, Hashable {
    let contentHash: String
    let date: Date
    let details: String
    let debit: Double
    let credit: Double
    let amount: Double
    var transactionType: TransactionType
    var category: CategoryID?
    var subcategory: SubcategoryID?
    var notes: String?
    let accountID: UUID

    /// In-memory only; populated by `AppViewModel` after loading edits.
    /// Never encoded — transactions are derived, not persisted.
    var edit: TransactionEdit?

    var id: String { contentHash }

    init(
        contentHash: String,
        date: Date,
        details: String,
        debit: Double,
        credit: Double,
        transactionType: TransactionType,
        category: CategoryID? = nil,
        subcategory: SubcategoryID? = nil,
        notes: String? = nil,
        accountID: UUID,
        edit: TransactionEdit? = nil
    ) {
        self.contentHash = contentHash
        self.date = date
        self.details = details
        self.debit = debit
        self.credit = credit
        self.amount = credit - debit
        self.transactionType = transactionType
        self.category = category
        self.subcategory = subcategory
        self.notes = notes
        self.accountID = accountID
        self.edit = edit
    }

    var effectiveCategory: CategoryID? {
        if let edit { return edit.category }
        return category
    }

    var effectiveSubcategory: SubcategoryID? {
        if let edit { return edit.subcategory }
        return subcategory
    }

    var effectiveNotes: String? {
        if let edit { return edit.notes }
        return notes
    }

    /// The parsed magnitude, re-signed by the effective type. The amount itself is
    /// not user-editable; a type override (e.g. expense → income) flips the sign so
    /// aggregate sums stay consistent with the transaction's classification.
    var effectiveAmount: Double {
        let magnitude = abs(amount)
        switch effectiveType {
        case .expense, .transfer_out: return -magnitude
        case .income, .transfer_in:   return magnitude
        }
    }

    var effectiveType: TransactionType {
        edit?.transactionType ?? transactionType
    }

}
