import Foundation

struct CategoryID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Synthetic sentinel for transactions with no category.
    /// Never stored in `categories.json`; used as a chart key and filter value.
    static let uncategorized = CategoryID(rawValue: "__uncategorized__")
}

struct SubcategoryID: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}
