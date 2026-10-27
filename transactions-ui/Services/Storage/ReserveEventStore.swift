import Foundation

/// Append-only store for `ReserveEvent`s, backed by `reserveEvents.json`.
/// This log is the single source of truth for reservation state — the net
/// per-(reserve,account) amounts consumed by the rest of the app are *derived*
/// from it via `foldEvents(_:)`.
final class ReserveEventStore {

    private let fileURL: URL
    private(set) var events: [ReserveEvent] = []

    init(fileURL: URL) { self.fileURL = fileURL }

    /// Load `reserveEvents.json`. If it does not exist, perform the one-time
    /// migration from the sibling `reservations.json`: emit one opening-balance
    /// allocation event per positive-amount reservation, then save. The legacy
    /// `reservations.json` is intentionally left on disk (no longer read).
    func load() throws {
        if let existing = try AtomicJSONFile.load([ReserveEvent].self, from: fileURL) {
            events = existing
            return
        }
        let legacyURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("reservations.json")
        if let legacy = try AtomicJSONFile.load([Reservation].self, from: legacyURL) {
            events = legacy
                .filter { $0.amount > 0 }
                .map {
                    ReserveEvent(
                        date: $0.updatedAt,
                        reserveID: $0.reserveID,
                        accountID: $0.accountID,
                        type: .allocation,
                        amount: $0.amount,
                        note: "Opening balance (migrated)"
                    )
                }
            try save()
            return
        }
        events = []
    }

    func save() throws {
        try AtomicJSONFile.save(events, to: fileURL)
    }

    func append(_ event: ReserveEvent) throws {
        events.append(event)
        try save()
    }

    /// Hard-remove a single event by id. Backs the per-row delete in the Activity
    /// table. This store primitive can remove any event type, but the app-level
    /// policy (`AppViewModel.deleteReserveEvent`) restricts the per-row delete to
    /// `.use` events. Foldd nets below 0.005 are dropped, so held never renders
    /// negative even if a deletion leaves a pair net-negative.
    func remove(eventID: UUID) throws {
        events.removeAll { $0.id == eventID }
        try save()
    }

    /// Cascade: drop every event for this reserve. Called on reserve deletion.
    func removeAll(reserveID: UUID) throws {
        events.removeAll { $0.reserveID == reserveID }
        try save()
    }

    /// Cascade: drop every event for this source account. Called on account deletion.
    func removeAll(accountID: UUID) throws {
        events.removeAll { $0.accountID == accountID }
        try save()
    }

    /// Wipe all events. DEBUG reset helper.
    func removeAll() throws {
        events.removeAll()
        try save()
    }
}
