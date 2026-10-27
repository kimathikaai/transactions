import Foundation

final class ReservationStore {

    private let fileURL: URL
    private(set) var reservations: [Reservation] = []

    init(fileURL: URL) { self.fileURL = fileURL }

    /// Load `reservations.json`. If it does not exist, fall back to the
    /// legacy `allocations.json` sibling. Either way, the next `save()`
    /// writes to `reservations.json` and the legacy file is removed.
    func load() throws {
        if let existing = try AtomicJSONFile.load([Reservation].self, from: fileURL) {
            reservations = existing
            return
        }
        let legacy = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("allocations.json")
        if let migrated = try AtomicJSONFile.load([Reservation].self, from: legacy) {
            reservations = migrated
            try save()
            try? FileManager.default.removeItem(at: legacy)
            return
        }
        reservations = []
    }

    func save() throws {
        try AtomicJSONFile.save(reservations, to: fileURL)
    }

    func upsert(_ record: Reservation) throws {
        if let idx = reservations.firstIndex(where: { $0.id == record.id }) {
            reservations[idx] = record
        } else {
            reservations.append(record)
        }
        try save()
    }

    func delete(id: UUID) throws {
        reservations.removeAll { $0.id == id }
        try save()
    }

    /// Cascade: drop every reservation whose `accountID == accountID`.
    /// Called after `AccountStore.delete(id:)`.
    func removeAll(accountID: UUID) throws {
        reservations.removeAll { $0.accountID == accountID }
        try save()
    }

    /// Cascade: drop every reservation whose `reserveID == reserveID`.
    func removeAll(reserveID: UUID) throws {
        reservations.removeAll { $0.reserveID == reserveID }
        try save()
    }

    /// Pure filter used on load. Splits `reservations` into the ones whose
    /// refs resolve and the ones that don't. Caller decides whether to log
    /// the dropped set. **Never** rewrites the file.
    static func validate(
        reservations: [Reservation],
        againstAccounts accountIDs: Set<UUID>,
        reserves reserveIDs: Set<UUID>
    ) -> (kept: [Reservation], dropped: [Reservation]) {
        var kept: [Reservation] = []
        var dropped: [Reservation] = []
        for r in reservations {
            if accountIDs.contains(r.accountID) && reserveIDs.contains(r.reserveID) {
                kept.append(r)
            } else {
                dropped.append(r)
            }
        }
        return (kept, dropped)
    }
}
