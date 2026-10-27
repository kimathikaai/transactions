import Foundation

enum ReserveError: Error, Equatable {
    case invalidAmount
    case insufficientFree(accountID: UUID, requested: Double, available: Double)
    case insufficientReservation(reserveID: UUID, accountID: UUID, requested: Double, available: Double)
    case transactionAlreadyLinked(contentHash: String)
}

extension ReserveError {
    /// Human-readable message for surfacing in claim/release UIs.
    /// Shared by `ReserveTransferSheet`.
    var userMessage: String {
        switch self {
        case .invalidAmount:
            return "Invalid amount"
        case .insufficientFree(_, let req, let avail):
            return "Only \(avail.formatted(.cad)) free (requested \(req.formatted(.cad)))"
        case .insufficientReservation(_, _, let req, let avail):
            return "Only \(avail.formatted(.cad)) here (requested \(req.formatted(.cad)))"
        case .transactionAlreadyLinked:
            return "This transaction is already used"
        }
    }
}

/// Mutates `ReserveEventStore` in response to reserve claim/release actions.
/// Callers pass in the precomputed `free` / per-(reserve,account) availability
/// values so this service doesn't need a view of every transaction —
/// `AppViewModel` computes those and hands them in. Each claim/release appends
/// an immutable event to the log; the net reservation amounts are derived from
/// the log via `foldEvents(_:)`.
struct ReserveService {

    let eventStore: ReserveEventStore

    init(eventStore: ReserveEventStore) {
        self.eventStore = eventStore
    }

    /// Move `amount` from the account's free pool into the reserve by appending
    /// an allocation event. Caller supplies `freeAvailable`.
    func claim(
        amount: Double,
        from account: Account,
        freeAvailable: Double,
        to reserve: Reserve,
        note: String?
    ) throws {
        guard amount > 0 else { throw ReserveError.invalidAmount }
        guard amount <= freeAvailable else {
            throw ReserveError.insufficientFree(
                accountID: account.id, requested: amount, available: freeAvailable
            )
        }
        try eventStore.append(ReserveEvent(
            reserveID: reserve.id, accountID: account.id,
            type: .allocation, amount: amount, note: note
        ))
    }

    /// Move `amount` back from the reserve to the account's free pool by
    /// appending a release event. Caller supplies the per-(reserve,account)
    /// available headroom.
    func release(
        amount: Double,
        from reserve: Reserve,
        to account: Account,
        availableForAccountInReserve available: Double,
        note: String?
    ) throws {
        guard amount > 0 else { throw ReserveError.invalidAmount }
        guard amount <= available else {
            throw ReserveError.insufficientReservation(
                reserveID: reserve.id, accountID: account.id,
                requested: amount, available: available
            )
        }
        try eventStore.append(ReserveEvent(
            reserveID: reserve.id, accountID: account.id,
            type: .release, amount: amount, note: note
        ))
    }

    /// Record that a real expense transaction spent money held in the reserve.
    /// Draws down the per-(reserve,account) held balance exactly like a release
    /// (caller supplies the same headroom), but tags the event `.use` and
    /// links the transaction. `alreadyLinked` is computed by the caller from the
    /// current set of used transaction hashes.
    func use(
        amount: Double,
        from source: Account,
        on reserve: Reserve,
        availableForAccountInReserve available: Double,
        transactionContentHash: String,
        alreadyLinked: Bool,
        note: String?
    ) throws {
        guard amount > 0 else { throw ReserveError.invalidAmount }
        guard !alreadyLinked else {
            throw ReserveError.transactionAlreadyLinked(contentHash: transactionContentHash)
        }
        guard amount <= available else {
            throw ReserveError.insufficientReservation(
                reserveID: reserve.id, accountID: source.id,
                requested: amount, available: available
            )
        }
        try eventStore.append(ReserveEvent(
            reserveID: reserve.id, accountID: source.id,
            type: .use, amount: amount, note: note,
            transactionContentHash: transactionContentHash
        ))
    }

    /// Delete a reserve and cascade-drop its events. `AppViewModel` calls this
    /// then refreshes its in-memory state.
    func deleteReserve(id: UUID, from reserveStore: ReserveStore) throws {
        try eventStore.removeAll(reserveID: id)
        try reserveStore.delete(id: id)
    }
}
