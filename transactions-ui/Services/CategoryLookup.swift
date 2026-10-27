import Foundation

/// Pure lookup helpers over a `[Category]` catalog. Stateless; every call
/// takes the catalog explicitly. Callers with hot loops should cache the
/// result of `byID` and pass it in where a helper accepts a byID map.
enum CategoryLookup {

    static func byID(_ categories: [Category]) -> [String: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    static func children(of parentID: String, in categories: [Category]) -> [Category] {
        categories.filter { $0.parent == parentID }
    }

    static func root(of leaf: Category, in byID: [String: Category]) -> Category? {
        guard let parentID = leaf.parent else { return leaf }
        return byID[parentID]
    }

    static func firstRoot(ofType type: TransactionType, in categories: [Category]) -> Category? {
        categories.first { $0.parent == nil && $0.transactionType == type }
    }

    /// Enforce the transfer type↔category coupling. A transfer type snaps to its
    /// matching transfer root (subcategory cleared); a non-transfer type strips any
    /// transfer-typed category to None. Non-transfer categories on non-transfer types
    /// pass through unchanged. Single source of truth reused by the edit UI's live
    /// `onChange` and the `AppViewModel.saveEdit` coercion.
    static func coerceCategory(
        for type: TransactionType,
        category: CategoryID?,
        subcategory: SubcategoryID?,
        in categories: [Category]
    ) -> (category: CategoryID?, subcategory: SubcategoryID?) {
        switch type {
        case .transfer_in, .transfer_out:
            let root = firstRoot(ofType: type, in: categories).map { CategoryID(rawValue: $0.id) }
            return (root, nil)
        case .expense, .income:
            if let category,
               let resolved = byID(categories)[category.rawValue],
               resolved.transactionType == .transfer_in || resolved.transactionType == .transfer_out {
                return (nil, nil)
            }
            return (category, subcategory)
        }
    }

    /// Flattens every leaf's `patterns` into the shape ImportPipeline consumes.
    /// Roots contribute nothing. Orphan leaves (parent missing from the
    /// catalog) are silently skipped — they surface in the debug panel as a
    /// structural violation.
    static func rules(from categories: [Category])
    -> [(txType: TransactionType, category: CategoryID, subcategory: SubcategoryID, pattern: String)] {
        let byIDMap = byID(categories)
        var out: [(TransactionType, CategoryID, SubcategoryID, String)] = []
        out.reserveCapacity(categories.reduce(0) { $0 + $1.patterns.count })
        for leaf in categories {
            guard let parentID = leaf.parent, let parent = byIDMap[parentID] else { continue }
            let catID = CategoryID(rawValue: parent.id)
            let subID = SubcategoryID(rawValue: leaf.id)
            for pattern in leaf.patterns {
                out.append((parent.transactionType, catID, subID, pattern))
            }
        }
        return out.map { (txType: $0.0, category: $0.1, subcategory: $0.2, pattern: $0.3) }
    }
}
