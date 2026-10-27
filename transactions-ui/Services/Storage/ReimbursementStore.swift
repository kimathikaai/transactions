import Foundation

/// Persists reimbursement links as a `[String: ReimbursementLink]` map keyed by
/// the reimbursed expense's `contentHash`, mirroring `EditStore`. The expense
/// hash being the key enforces "one reimbursement per expense" (US3). This is a
/// flat mutable record store — there is no allocate/release lifecycle, so no
/// event log (unlike reserves).
final class ReimbursementStore {

    private let fileURL: URL
    private(set) var links: [String: ReimbursementLink] = [:]

    init(fileURL: URL) { self.fileURL = fileURL }

    /// Reads the file into memory. Missing file → empty map (fresh checkout or
    /// first launch).
    func load() throws {
        links = try AtomicJSONFile.load([String: ReimbursementLink].self, from: fileURL) ?? [:]
    }

    func save() throws {
        try AtomicJSONFile.save(links, to: fileURL)
    }

    /// Insert or replace the link for the given reimbursed-expense hash, then persist.
    func upsert(expenseHash: String, record: ReimbursementLink) throws {
        links[expenseHash] = record
        try save()
    }

    /// Remove the link for the given reimbursed-expense hash. No-op if not found, then persist.
    func delete(expenseHash: String) throws {
        links.removeValue(forKey: expenseHash)
        try save()
    }

    func replaceAll(_ next: [String: ReimbursementLink]) throws {
        links = next
        try save()
    }
}
