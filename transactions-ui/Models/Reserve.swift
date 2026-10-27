import Foundation

/// Value-type reserve record. Persisted as one element of `reserves.json`.
/// Derived quantities (`total`, `progress`, `hasTarget`, `isAtTarget`,
/// `reservation(from:)`, `amount(from:)`) live in `ReserveComputations.swift`
/// and take an `[Reservation]` list as a parameter.
// Equality is synthesized full-struct (not id-only): SwiftUI's `ForEach`
// compares elements with `==` to decide whether a row changed, so an id-only
// `==` would make an edited reserve (same id) look unchanged and the list row
// would never re-render.
struct Reserve: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var emoji: String
    var colorHex: String
    var target: Double
    var tagline: String
    var createdAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        colorHex: String,
        target: Double = 0,
        tagline: String = "",
        createdAt: Date = .now,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.target = target
        self.tagline = tagline
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
