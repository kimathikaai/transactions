import Foundation

/// Immutable append-only ledger entry for a single reserve movement.
/// Allocations add to the derived per-(reserve,account) balance; releases and
/// uses subtract from it. A use additionally links a real expense
/// transaction (via `transactionContentHash`) — it records money that was saved
/// and then actually spent toward the goal. The sum of all events is the single
/// source of truth for reservations. Persisted as one element of `reserveEvents.json`.
enum ReserveEventType: String, Codable {
    case allocation
    case release
    case use

    /// Tolerant decode: legacy ledgers persisted the use event as `"exercise"`.
    /// Map that raw value onto `.use` so old data still loads; new/re-saved data
    /// encodes as `"use"` via the synthesized raw value.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "use", "exercise":
            self = .use
        default:
            guard let value = ReserveEventType(rawValue: raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown ReserveEventType \"\(raw)\""
                ))
            }
            self = value
        }
    }
}

struct ReserveEvent: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var date: Date
    var reserveID: UUID
    var accountID: UUID
    var type: ReserveEventType
    var amount: Double
    var note: String?
    /// contentHash of the linked expense transaction; set only on `.use`
    /// events. Persisted as-is (no denormalized snapshot) and resolved to a live
    /// transaction at display time — a dangling hash renders as "(unlinked)".
    var transactionContentHash: String?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        reserveID: UUID,
        accountID: UUID,
        type: ReserveEventType,
        amount: Double,
        note: String? = nil,
        transactionContentHash: String? = nil
    ) {
        self.id = id
        self.date = date
        self.reserveID = reserveID
        self.accountID = accountID
        self.type = type
        self.amount = amount
        self.note = note
        self.transactionContentHash = transactionContentHash
    }

    enum CodingKeys: String, CodingKey {
        case id, date, reserveID, accountID, type, amount, note, transactionContentHash
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self, forKey: .id)
        date      = try c.decode(Date.self, forKey: .date)
        reserveID = try c.decode(UUID.self, forKey: .reserveID)
        accountID = try c.decode(UUID.self, forKey: .accountID)
        type      = try c.decode(ReserveEventType.self, forKey: .type)
        amount    = try c.decode(Double.self, forKey: .amount)
        note      = try c.decodeIfPresent(String.self, forKey: .note)
        transactionContentHash = try c.decodeIfPresent(String.self, forKey: .transactionContentHash)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,        forKey: .id)
        try c.encode(date,      forKey: .date)
        try c.encode(reserveID, forKey: .reserveID)
        try c.encode(accountID, forKey: .accountID)
        try c.encode(type,      forKey: .type)
        try c.encode(amount,    forKey: .amount)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(transactionContentHash, forKey: .transactionContentHash)
    }
}
