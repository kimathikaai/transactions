import Foundation

/// Value-type reservation record: `amount` reserved from `accountID` for
/// `reserveID`. Persisted as one element of `reservations.json`.
struct Reservation: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var amount: Double
    var updatedAt: Date
    var reserveID: UUID
    var accountID: UUID

    init(
        id: UUID = UUID(),
        amount: Double,
        updatedAt: Date = .now,
        reserveID: UUID,
        accountID: UUID
    ) {
        self.id = id
        self.amount = amount
        self.updatedAt = updatedAt
        self.reserveID = reserveID
        self.accountID = accountID
    }

    enum CodingKeys: String, CodingKey {
        case id, amount, updatedAt, reserveID, accountID
        // Legacy alias — decode-only; reads pre-rename records that still
        // use the `bucketID` key. Encoding always emits `reserveID`.
        case bucketID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,   forKey: .id)
        amount    = try c.decode(Double.self, forKey: .amount)
        updatedAt = try c.decode(Date.self,   forKey: .updatedAt)
        accountID = try c.decode(UUID.self,   forKey: .accountID)
        // Prefer the new key; fall back to legacy.
        if let rid = try c.decodeIfPresent(UUID.self, forKey: .reserveID) {
            reserveID = rid
        } else {
            reserveID = try c.decode(UUID.self, forKey: .bucketID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,        forKey: .id)
        try c.encode(amount,    forKey: .amount)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(reserveID, forKey: .reserveID)
        try c.encode(accountID, forKey: .accountID)
        // .bucketID intentionally omitted from encoding.
    }
}
