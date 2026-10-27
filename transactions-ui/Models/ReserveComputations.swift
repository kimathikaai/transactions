import Foundation

extension Account {
    /// Whether this account participates in the reservoir.
    /// Debt accounts are excluded; everything else (chequing, savings,
    /// investment) counts.
    var isReservoirSource: Bool {
        type != .debt
    }
}

// MARK: - Account computations (over transaction / reservation lists)

/// `initialBalance` + Σ effective amount of every transaction on this account.
func netBalance(of account: Account, transactions: [Transaction]) -> Double {
    account.initialBalance + transactions
        .lazy
        .filter { $0.accountID == account.id }
        .reduce(0) { $0 + $1.effectiveAmount }
}

/// Σ amount of reservations originating from this account.
func allotted(for accountID: UUID, reservations: [Reservation]) -> Double {
    reservations.lazy.filter { $0.accountID == accountID }.reduce(0) { $0 + $1.amount }
}

/// Reservoir headroom: balance not yet committed to any reserve.
func free(
    of account: Account,
    transactions: [Transaction],
    reservations: [Reservation]
) -> Double {
    netBalance(of: account, transactions: transactions)
        - allotted(for: account.id, reservations: reservations)
}

// MARK: - Reserve computations (over reservation list)

/// Σ amount of reservations across all sources for this reserve. Because the
/// event fold nets allocations minus releases minus uses, this is the
/// currently *held* (still-reserved, not-yet-spent) amount.
func total(of reserveID: UUID, reservations: [Reservation]) -> Double {
    reservations.lazy.filter { $0.reserveID == reserveID }.reduce(0) { $0 + $1.amount }
}

/// The reservation row for this (reserve, account) pair, if one exists.
func reservation(
    reserveID: UUID,
    accountID: UUID,
    in reservations: [Reservation]
) -> Reservation? {
    reservations.first { $0.reserveID == reserveID && $0.accountID == accountID }
}

/// Amount allocated to this reserve from the given account, or 0 if none.
func amount(
    reserveID: UUID,
    accountID: UUID,
    in reservations: [Reservation]
) -> Double {
    reservation(reserveID: reserveID, accountID: accountID, in: reservations)?.amount ?? 0
}

/// Whether this reserve has a meaningful target (> 0). Legacy reserves
/// default to 0; the card hides its progress block for those.
func hasTarget(_ reserve: Reserve) -> Bool {
    reserve.target > 0
}

/// Filled fraction of the progress bar, capped at 1. The card shows
/// over-target reserves with a full bar plus the literal amounts.
func progress(of reserve: Reserve, reservations: [Reservation]) -> Double {
    guard reserve.target > 0 else { return 0 }
    return min(1, total(of: reserve.id, reservations: reservations) / reserve.target)
}

/// True when the reserve's total has reached or passed the target.
func isAtTarget(_ reserve: Reserve, reservations: [Reservation]) -> Bool {
    reserve.target > 0 && total(of: reserve.id, reservations: reservations) >= reserve.target
}

// MARK: - Use computations (over event log)

/// Σ amount of `.use` events for this reserve — cumulative money that was
/// spent toward the goal. Unlike `total` (held), this never decreases; it is the
/// "spent" sub-segment of the progress bar.
func used(of reserveID: UUID, events: [ReserveEvent]) -> Double {
    events.lazy
        .filter { $0.reserveID == reserveID && $0.type == .use }
        .reduce(0) { $0 + $1.amount }
}

/// contentHashes of every transaction already linked to a use event.
/// Used to block linking the same expense twice.
func usedTransactionIDs(events: [ReserveEvent]) -> Set<String> {
    Set(events.lazy.filter { $0.type == .use }.compactMap(\.transactionContentHash))
}

/// The filled portion of the reserve's progress bar: held (still reserved) plus
/// used (spent) = Σallocation − Σrelease. This is invariant to using —
/// spending merely shifts money from the held sub-segment to the used one —
/// so the headline percentage does not regress when a goal is spent.
func filled(of reserve: Reserve, reservations: [Reservation], events: [ReserveEvent]) -> Double {
    total(of: reserve.id, reservations: reservations) + used(of: reserve.id, events: events)
}

/// Filled fraction (held + used) of the progress bar, capped at 1.
func filledProgress(of reserve: Reserve, reservations: [Reservation], events: [ReserveEvent]) -> Double {
    guard reserve.target > 0 else { return 0 }
    return min(1, filled(of: reserve, reservations: reservations, events: events) / reserve.target)
}

/// True when held + used has reached or passed the target.
func isAtFilledTarget(_ reserve: Reserve, reservations: [Reservation], events: [ReserveEvent]) -> Bool {
    reserve.target > 0 && filled(of: reserve, reservations: reservations, events: events) >= reserve.target
}

/// Filter an account list down to the reservoir-eligible subset.
func reservoirSources(_ accounts: [Account]) -> [Account] {
    accounts.filter(\.isReservoirSource)
}

// MARK: - Progress fractions

/// Fraction of a balance that is reserved, clamped to [0, 1]. A non-positive
/// balance yields 1 when anything is reserved (over-committed → full bar), else
/// 0. Shared by the reservoir summary and per-source rows so the edge behavior
/// is defined once.
func reservedFraction(reserved: Double, balance: Double) -> Double {
    guard balance > 0 else { return reserved > 0 ? 1 : 0 }
    return min(max(reserved / balance, 0), 1)
}

// MARK: - Event-log fold (source of truth → derived reservations)

/// Fold an append-only `ReserveEvent` log into the net-amount `[Reservation]`
/// array the rest of the app consumes. Allocations add; releases and uses
/// subtract, per (reserveID, accountID) pair. Pairs whose net falls below 0.005
/// are dropped (fully released/spent). Each derived reservation's `updatedAt` is
/// the latest event date for that pair.
func foldEvents(_ events: [ReserveEvent]) -> [Reservation] {
    struct Key: Hashable { let reserve: UUID; let account: UUID }
    var running: [Key: (amount: Double, latest: Date)] = [:]

    for event in events {
        let key = Key(reserve: event.reserveID, account: event.accountID)
        let delta = event.type == .allocation ? event.amount : -event.amount
        let previous = running[key]
        let latest = previous.map { Swift.max($0.latest, event.date) } ?? event.date
        running[key] = ((previous?.amount ?? 0) + delta, latest)
    }

    return running.compactMap { key, value in
        guard value.amount >= 0.005 else { return nil }
        return Reservation(
            amount: value.amount,
            updatedAt: value.latest,
            reserveID: key.reserve,
            accountID: key.account
        )
    }
}
