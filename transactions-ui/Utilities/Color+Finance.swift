import SwiftUI

extension Color {
    static let income = Color(hex: "#6FCF97")
    static let expense = Color(hex: "#EB5757")

    /// Shared tint for reserved amounts: the reservoir-card number and its
    /// progress-bar fill. Kept as a semantic token so both stay in sync.
    static let reserved = Color(hex: "#DEDEDE")
    static let unreserved = Color(hex: "#777777")

    /// Tint for used (spent) amounts: the leading "spent" sub-segment of a
    /// reserve's progress bar and the Activity table's Use rows.
    static let spent = Color(hex: "#56A3A6")
}
