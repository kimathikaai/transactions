import Foundation

final class ReserveStore {

    private let fileURL: URL
    private(set) var reserves: [Reserve] = []

    init(fileURL: URL) { self.fileURL = fileURL }

    /// Load `reserves.json`. If it does not exist, fall back to the
    /// legacy `buckets.json` sibling. Either way, the next `save()`
    /// writes to `reserves.json` and the legacy file is removed.
    func load() throws {
        if let existing = try AtomicJSONFile.load([Reserve].self, from: fileURL) {
            reserves = existing
            return
        }
        let legacy = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("buckets.json")
        if let migrated = try AtomicJSONFile.load([Reserve].self, from: legacy) {
            reserves = migrated
            try save()
            try? FileManager.default.removeItem(at: legacy)
            return
        }
        reserves = []
    }

    func save() throws {
        try AtomicJSONFile.save(reserves, to: fileURL)
    }

    func upsert(_ record: Reserve) throws {
        if let idx = reserves.firstIndex(where: { $0.id == record.id }) {
            reserves[idx] = record
        } else {
            reserves.append(record)
        }
        try save()
    }

    func delete(id: UUID) throws {
        reserves.removeAll { $0.id == id }
        try save()
    }
}
