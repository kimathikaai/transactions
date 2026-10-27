import Foundation

/// Value-type record of a single reimbursed expense, keyed on disk by the
/// reimbursed expense's `contentHash` (so each expense has at most one link —
/// this enforces "one reimbursement per expense"). The link draws from a
/// reimbursement income identified by `reimbursementHash`.
///
/// `amount` is a **snapshot** computed as `min(|expense|, the income's remaining
/// pool)` at link time and never recomputed — to change it, unlink and re-link.
/// Persisted as one value of `reimbursements.json` (a `[String: ReimbursementLink]`
/// keyed by expense hash), mirroring `edits.json`.
struct ReimbursementLink: Codable, Equatable, Hashable {
    /// contentHash of the reimbursement income this link draws from. Resolved to
    /// a live transaction at display time — a dangling hash renders as unlinked.
    var reimbursementHash: String
    /// Snapshot of the reimbursed amount at link time (never recomputed).
    var amount: Double
    /// When the link was made; drives the newest-first review list.
    var linkedAt: Date
    /// Optional free-text note, mirroring reserve-event notes.
    var note: String?

    init(
        reimbursementHash: String,
        amount: Double,
        linkedAt: Date = .now,
        note: String? = nil
    ) {
        self.reimbursementHash = reimbursementHash
        self.amount = amount
        self.linkedAt = linkedAt
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case reimbursementHash, amount, linkedAt, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reimbursementHash = try c.decode(String.self, forKey: .reimbursementHash)
        amount            = try c.decode(Double.self, forKey: .amount)
        linkedAt          = try c.decode(Date.self, forKey: .linkedAt)
        note              = try c.decodeIfPresent(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(reimbursementHash, forKey: .reimbursementHash)
        try c.encode(amount,            forKey: .amount)
        try c.encode(linkedAt,          forKey: .linkedAt)
        try c.encodeIfPresent(note,     forKey: .note)
    }
}
