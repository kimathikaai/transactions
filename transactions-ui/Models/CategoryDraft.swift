import Foundation

/// Editor-friendly value type. Turned into a `Category` at commit time by
/// `CategoryStore.add`. `displayName` whitespace is normalized at the
/// mutation entry points (`AppViewModel.addCategory` / `renameCategory`).
struct CategoryDraft: Equatable, Sendable {
    var displayName: String
    var parent: String?
    var color: String
    var symbol: String
    var transactionType: TransactionType
    var patterns: [String]

    func materialize(id: String = CategoryFactory.newID()) -> Category {
        Category(
            id: id,
            displayName: displayName,
            parent: parent,
            color: color,
            symbol: symbol,
            transactionType: transactionType,
            patterns: patterns
        )
    }
}
