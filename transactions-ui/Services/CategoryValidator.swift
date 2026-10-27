import Foundation

enum BrokenField: String, Sendable {
    case category
    case subcategory
}

struct BrokenEdit: Identifiable, Equatable, Sendable {
    let id: UUID
    let contentHash: String
    let field: BrokenField
    let referencedID: String

    init(contentHash: String, field: BrokenField, referencedID: String) {
        self.id = UUID()
        self.contentHash = contentHash
        self.field = field
        self.referencedID = referencedID
    }
}

enum ViolationKind: String, Sendable {
    case orphanLeaf
    case parentIsLeaf
    case transactionTypeMismatch
    case duplicateDisplayName
}

struct StructuralViolation: Identifiable, Equatable, Sendable {
    let id: UUID
    let categoryID: String
    let displayName: String
    let kind: ViolationKind

    init(categoryID: String, displayName: String, kind: ViolationKind) {
        self.id = UUID()
        self.categoryID = categoryID
        self.displayName = displayName
        self.kind = kind
    }
}

struct StaleEditRef: Identifiable, Equatable, Sendable {
    let id: UUID
    let contentHash: String

    init(contentHash: String) {
        self.id = UUID()
        self.contentHash = contentHash
    }
}

struct CategoryValidationResult: Equatable, Sendable {
    var brokenEdits: [BrokenEdit]
    var structuralViolations: [StructuralViolation]
    var staleRefs: [StaleEditRef]

    static let empty = CategoryValidationResult(brokenEdits: [], structuralViolations: [], staleRefs: [])
}

/// Pure. Called from `AppViewModel` after load and after every category
/// mutation. Results feed the debug panel — no fixes here, visibility only.
enum CategoryValidator {

    static func validate(
        categories: [Category],
        edits: [String: TransactionEdit],
        transactions: [Transaction]
    ) -> CategoryValidationResult {
        let byID = CategoryLookup.byID(categories)

        // Broken edits.
        var broken: [BrokenEdit] = []
        for (hash, edit) in edits {
            if let cid = edit.category, byID[cid.rawValue] == nil {
                broken.append(BrokenEdit(contentHash: hash, field: .category, referencedID: cid.rawValue))
            }
            if let sid = edit.subcategory, byID[sid.rawValue] == nil {
                broken.append(BrokenEdit(contentHash: hash, field: .subcategory, referencedID: sid.rawValue))
            }
        }

        // Structural violations.
        var violations: [StructuralViolation] = []
        for c in categories where c.parent != nil {
            guard let parent = byID[c.parent!] else {
                violations.append(StructuralViolation(categoryID: c.id, displayName: c.displayName, kind: .orphanLeaf))
                continue
            }
            if parent.parent != nil {
                violations.append(StructuralViolation(categoryID: c.id, displayName: c.displayName, kind: .parentIsLeaf))
            }
            if parent.transactionType != c.transactionType {
                violations.append(StructuralViolation(categoryID: c.id, displayName: c.displayName, kind: .transactionTypeMismatch))
            }
        }

        // Duplicate display names: emit one violation per duplicated record.
        let nameCounts = Dictionary(grouping: categories, by: \.displayName).mapValues(\.count)
        for c in categories where (nameCounts[c.displayName] ?? 0) > 1 {
            violations.append(StructuralViolation(categoryID: c.id, displayName: c.displayName, kind: .duplicateDisplayName))
        }

        // Stale references.
        let liveHashes = Set(transactions.map(\.contentHash))
        let stale = edits.keys
            .filter { !liveHashes.contains($0) }
            .sorted()
            .map(StaleEditRef.init(contentHash:))

        return CategoryValidationResult(
            brokenEdits: broken.sorted { $0.contentHash < $1.contentHash },
            structuralViolations: violations.sorted { ($0.displayName, $0.categoryID) < ($1.displayName, $1.categoryID) },
            staleRefs: stale
        )
    }
}
