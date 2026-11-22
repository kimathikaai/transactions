import Foundation

/// Persists reimbursement links as a `[String: [ReimbursementLink]]` map keyed by
/// the reimbursed expense's `contentHash`: one entry per expense, holding every
/// income that pays part of it back (at most one link per expense/income pair).
/// An expense with no links has no key. This is a flat mutable record store —
/// there is no allocate/release lifecycle, so no event log (unlike reserves).
///
/// Legacy files stored one link per expense (`[String: ReimbursementLink]`);
/// `load` still reads them, and the next write saves the list format.
final class ReimbursementStore {

    private let fileURL: URL
    private(set) var links: [String: [ReimbursementLink]] = [:]

    init(fileURL: URL) { self.fileURL = fileURL }

    /// Reads the file into memory. Missing file → empty map (fresh checkout or
    /// first launch). Falls back to the legacy one-link-per-expense format.
    func load() throws {
        do {
            links = try AtomicJSONFile.load([String: [ReimbursementLink]].self, from: fileURL) ?? [:]
        } catch {
            guard let legacy = try? AtomicJSONFile.load([String: ReimbursementLink].self, from: fileURL) else {
                throw error
            }
            links = legacy.mapValues { [$0] }
        }
    }

    func save() throws {
        try AtomicJSONFile.save(links, to: fileURL)
    }

    /// Append a link to the given reimbursed-expense hash, then persist.
    func add(expenseHash: String, record: ReimbursementLink) throws {
        links[expenseHash, default: []].append(record)
        try save()
    }

    /// Remove the link between the given expense and income, dropping the
    /// expense's key when it was the last one. No-op if not found, then persist.
    func delete(expenseHash: String, incomeHash: String) throws {
        let remaining = (links[expenseHash] ?? []).filter { $0.reimbursementHash != incomeHash }
        links[expenseHash] = remaining.isEmpty ? nil : remaining
        try save()
    }

    func replaceAll(_ next: [String: [ReimbursementLink]]) throws {
        links = next
        try save()
    }
}
