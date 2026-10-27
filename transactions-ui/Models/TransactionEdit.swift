import Foundation

/// Value-type override for a single transaction, keyed on disk by the
/// transaction's `contentHash`. Optional fields let a partial edit express
/// "override category but leave notes untouched." A `nil` category still
/// overrides — it represents "user explicitly set to None."
struct TransactionEdit: Codable, Equatable, Hashable {
    var category: CategoryID?
    var subcategory: SubcategoryID?
    var notes: String?
    var transactionType: TransactionType?
    var updatedAt: Date

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case category
        case subcategory
        case notes
        case transactionType
        case updatedAt
    }

    init(
        category: CategoryID? = nil,
        subcategory: SubcategoryID? = nil,
        notes: String? = nil,
        transactionType: TransactionType? = nil,
        updatedAt: Date = .now
    ) {
        self.category = category
        self.subcategory = subcategory
        self.notes = notes
        self.transactionType = transactionType
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.category = try c.decodeIfPresent(String.self, forKey: .category).map(CategoryID.init(rawValue:))
        self.subcategory = try c.decodeIfPresent(String.self, forKey: .subcategory).map(SubcategoryID.init(rawValue:))
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.transactionType = try c.decodeIfPresent(String.self, forKey: .transactionType).flatMap(TransactionType.init(rawValue:))
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(category?.rawValue, forKey: .category)
        try c.encodeIfPresent(subcategory?.rawValue, forKey: .subcategory)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(transactionType?.rawValue, forKey: .transactionType)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
