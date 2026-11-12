import Foundation

extension LinkKind {
    /// The kind a manual link between `x` and `y` gets: `transfer` when they're
    /// opposite-direction transfers in different accounts and neither already
    /// has a transfer link; otherwise `related`. Amounts don't matter here —
    /// a manual transfer can differ (e.g. a fee taken in transit).
    static func inferred(_ x: Transaction, _ y: Transaction, eitherHasTransferLink: Bool) -> LinkKind {
        let types: Set<TransactionType> = [x.effectiveType, y.effectiveType]
        let isTransferPair = types == [.transfer_out, .transfer_in]
        guard isTransferPair, x.accountID != y.accountID, !eitherHasTransferLink else { return .related }
        return .transfer
    }
}

extension TransactionType {
    /// The type the other side of this transaction usually has: transfers flip
    /// direction; income and expense stay as they are.
    var mirrored: TransactionType {
        switch self {
        case .transfer_out: return .transfer_in
        case .transfer_in:  return .transfer_out
        case .income, .expense: return self
        }
    }
}

/// Pairs opposite-direction transfers automatically: different accounts, the
/// same amount to the cent, at most `windowDays` apart. Pure and deterministic —
/// recomputed on every load and never persisted.
enum TransferAutoPairer {

    static let windowDays = 3

    /// Whole days between two dates (rounded, so DST shifts don't matter).
    static func dayGap(_ x: Date, _ y: Date) -> Int {
        Int((abs(x.timeIntervalSince(y)) / 86_400).rounded())
    }

    /// The magnitude in whole cents, so float noise (`0.1 + 0.2`) still compares equal.
    static func cents(_ amount: Double) -> Int {
        Int((abs(amount) * 100).rounded())
    }

    /// Every auto-pair among `transactions`. `blocked` hashes (those with a live
    /// manual transfer link) never pair; `excludedPairs` (rejections and manual
    /// links) are never proposed. Ties resolve greedily by (day gap, out date,
    /// out hash, in hash), so the result is stable from load to load.
    static func pairs(
        in transactions: [Transaction],
        blocked: Set<String>,
        excludedPairs: Set<HashPair>
    ) -> [HashPair] {
        let eligible = transactions.filter { !blocked.contains($0.contentHash) }
        let outsByCents = Dictionary(grouping: eligible.filter { $0.effectiveType == .transfer_out }) { cents($0.amount) }
        let insByCents = Dictionary(grouping: eligible.filter { $0.effectiveType == .transfer_in }) { cents($0.amount) }

        var candidates: [(gap: Int, out: Transaction, in: Transaction)] = []
        for (amount, outs) in outsByCents {
            for out in outs {
                for inn in insByCents[amount] ?? [] {
                    let gap = dayGap(out.date, inn.date)
                    guard out.accountID != inn.accountID,
                          gap <= windowDays,
                          !excludedPairs.contains(HashPair(out.contentHash, inn.contentHash))
                    else { continue }
                    candidates.append((gap, out, inn))
                }
            }
        }

        candidates.sort {
            ($0.gap, $0.out.date, $0.out.contentHash, $0.in.contentHash)
                < ($1.gap, $1.out.date, $1.out.contentHash, $1.in.contentHash)
        }

        var taken: Set<String> = []
        var result: [HashPair] = []
        for candidate in candidates
        where !taken.contains(candidate.out.contentHash) && !taken.contains(candidate.in.contentHash) {
            taken.insert(candidate.out.contentHash)
            taken.insert(candidate.in.contentHash)
            result.append(HashPair(candidate.out.contentHash, candidate.in.contentHash))
        }
        return result
    }
}

/// Orders the Links section's "link to existing" table. Ranked, not filtered:
/// rows with the same amount within the auto-pair window come first (closest
/// date first), then everything else in input order (newest first).
enum LinkCandidates {
    static func ranked(
        for source: Transaction,
        from snapshots: [TransactionSnapshot],
        alreadyLinked: Set<String>
    ) -> [TransactionSnapshot] {
        let sourceCents = TransferAutoPairer.cents(source.amount)
        var near: [(gap: Int, offset: Int, snap: TransactionSnapshot)] = []
        var others: [TransactionSnapshot] = []
        for (offset, snap) in snapshots.enumerated()
        where snap.id != source.contentHash && !alreadyLinked.contains(snap.id) {
            let gap = TransferAutoPairer.dayGap(snap.date, source.date)
            if TransferAutoPairer.cents(snap.effectiveAmount) == sourceCents, gap <= TransferAutoPairer.windowDays {
                near.append((gap, offset, snap))
            } else {
                others.append(snap)
            }
        }
        near.sort { ($0.gap, $0.offset) < ($1.gap, $1.offset) }
        return near.map(\.snap) + others
    }
}

/// Defaults for the Links section's "Create & link new" form.
enum CreateLinkDefaults {
    /// A suggested description for the new row; empty when there's no good guess.
    static func details(for type: TransactionType, sourceAccountName: String) -> String {
        switch type {
        case .transfer_in:  return "Transfer from \(sourceAccountName)"
        case .transfer_out: return "Transfer to \(sourceAccountName)"
        case .income, .expense: return ""
        }
    }

    /// Where the new row can go: every account, except the source's own when
    /// the source is a transfer (a transfer's other side is in another account).
    static func accountChoices(for source: Transaction, in accounts: [Account]) -> [Account] {
        let isTransfer = source.effectiveType == .transfer_in || source.effectiveType == .transfer_out
        return isTransfer ? accounts.filter { $0.id != source.accountID } : accounts
    }
}
