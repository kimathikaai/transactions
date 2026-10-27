import Foundation

final class EditStore {

    private let fileURL: URL
    private(set) var edits: [String: TransactionEdit] = [:]

    init(fileURL: URL) { self.fileURL = fileURL }

    /// Reads the file into memory. Missing file → empty dict (fresh checkout
    /// or first launch).
    func load() throws {
        edits = try AtomicJSONFile.load([String: TransactionEdit].self, from: fileURL) ?? [:]
    }

    func save() throws {
        try AtomicJSONFile.save(edits, to: fileURL)
    }

    /// Insert or replace the record for the given content hash, then persist.
    func upsert(contentHash: String, record: TransactionEdit) throws {
        edits[contentHash] = record
        try save()
    }

    /// Remove the record for the given content hash. No-op if not found, then persist.
    func delete(contentHash: String) throws {
        edits.removeValue(forKey: contentHash)
        try save()
    }

    func replaceAll(_ next: [String: TransactionEdit]) throws {
        edits = next
        try save()
    }
}
