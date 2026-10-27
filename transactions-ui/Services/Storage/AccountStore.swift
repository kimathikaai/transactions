import Foundation

/// Owner of `accounts.json`. Every mutation is write-through: mutate the
/// in-memory array, then atomically rewrite the file.
final class AccountStore {

    private let fileURL: URL
    private(set) var accounts: [Account] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Reads the file into memory. Missing file → empty list (fresh checkout
    /// or first launch).
    func load() throws {
        accounts = try AtomicJSONFile.load([Account].self, from: fileURL) ?? []
    }

    func save() throws {
        try AtomicJSONFile.save(accounts, to: fileURL)
    }

    /// Insert or replace by id.
    func upsert(_ record: Account) throws {
        if let idx = accounts.firstIndex(where: { $0.id == record.id }) {
            accounts[idx] = record
        } else {
            accounts.append(record)
        }
        try save()
    }

    /// Remove by id. No-op if not found.
    func delete(id: UUID) throws {
        accounts.removeAll { $0.id == id }
        try save()
    }
}
