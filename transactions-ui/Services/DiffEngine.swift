import Foundation

struct CSVDiff {
    let added: [Transaction]
    let removed: [Transaction]

    var isEmpty: Bool { added.isEmpty && removed.isEmpty }
}

/// Pure set-difference between an account's existing transactions and a fresh import.
/// Identity is `contentHash` — same inputs produce the same hash, so re-uploading the
/// identical CSV yields zero added and zero removed.
///
/// PRECONDITION: both `existing` and `incoming` must have unique contentHashes within
/// each list. `Dictionary(uniqueKeysWithValues:)` will trap on a collision. This holds
/// for both sides because `ImportPipeline.makeTransactions` bakes a per-row occurrence
/// index into the hash — byte-identical CSV rows therefore produce distinct hashes by
/// construction, and `existing` is just an earlier snapshot of the same pipeline output.
enum DiffEngine {

    static func diff(existing: [Transaction], incoming: [Transaction]) -> CSVDiff {
        let existingByHash = Dictionary(uniqueKeysWithValues: existing.map { ($0.contentHash, $0) })
        let incomingByHash = Dictionary(uniqueKeysWithValues: incoming.map { ($0.contentHash, $0) })

        let added = incoming.filter { existingByHash[$0.contentHash] == nil }
        let removed = existing.filter { incomingByHash[$0.contentHash] == nil }

        return CSVDiff(added: added, removed: removed)
    }
}
