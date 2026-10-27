import Foundation

/// Flat, editable category record persisted to `Data/categories.json`.
/// Depth is capped at 2: a record is either a root (`parent == nil`) or a
/// leaf whose `parent` references a root's id. `displayName` is globally
/// unique across the catalog; `transactionType` is fixed at creation.
struct Category: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var displayName: String
    var parent: String?
    var color: String
    var symbol: String
    let transactionType: TransactionType
    var patterns: [String]

    var isRoot: Bool { parent == nil }
    var isLeaf: Bool { parent != nil }
}

/// Mints the synthetic `cat_<uuid>` ids used everywhere.
enum CategoryFactory {
    static func newID() -> String {
        "cat_" + UUID().uuidString.lowercased()
    }
}
