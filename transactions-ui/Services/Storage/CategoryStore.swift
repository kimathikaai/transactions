import Foundation

/// Owner of `categories.json`. Thin persistence wrapper following the same
/// shape as `AccountStore` / `ReserveStore` / `ReservationStore`: mutate the
/// in-memory array, then atomically rewrite the file. Op-level validation
/// (uniqueness, parent-exists, transactionType-match) lives in
/// `CategoryValidator` and is enforced by the caller — not here.
final class CategoryStore {

    private let fileURL: URL
    private(set) var categories: [Category] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Reads the file into memory. Missing file → empty list (fresh checkout
    /// or first launch).
    func load() throws {
        categories = try AtomicJSONFile.load([Category].self, from: fileURL) ?? []
    }

    func save() throws {
        try AtomicJSONFile.save(categories, to: fileURL)
    }

    /// Insert or replace by id, preserving array order.
    func upsert(_ record: Category) throws {
        if let idx = categories.firstIndex(where: { $0.id == record.id }) {
            categories[idx] = record
        } else {
            categories.append(record)
        }
        try save()
    }

    /// Remove by id. No-op if not found.
    func delete(id: String) throws {
        categories.removeAll { $0.id == id }
        try save()
    }

    /// Rewrite the whole array in one shot. Used by merge (which computes a
    /// new array in memory and commits atomically) and by tests.
    func replaceAll(_ next: [Category]) throws {
        categories = next
        try save()
    }
}
