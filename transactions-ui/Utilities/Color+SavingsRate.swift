import SwiftUI

extension Color {
    /// Maps a savings rate in [-1, 1] to a 3-stop gradient:
    /// red (-100%) → orange (0%) → green (+100%).
    /// `nil` rate (no income) returns a muted gray.
    static func savingsRate(_ rate: Double?) -> Color {
        guard let rate else { return Color.secondary.opacity(0.18) }
        let green  = (r: 0.22, g: 0.73, b: 0.43)
        let orange = (r: 0.98, g: 0.65, b: 0.18)
        let red    = (r: 0.91, g: 0.28, b: 0.24)
        if rate >= 0 {
            return lerp(orange, green, t: rate)
        } else {
            return lerp(red, orange, t: rate + 1)
        }
    }

    /// Maps a clamped savings rate amount in [0, 1] to a 3-stop gradient:
    /// red (0%) → orange (10%) → green (100%).
    /// `nil` returns muted gray.
    static func savingsRateAmount(_ rate: Double?) -> Color {
        guard let rate else { return Color.secondary.opacity(0.18) }
        let clamped = max(0, min(1, rate))
        let red    = (r: 0.91, g: 0.28, b: 0.24)
        let orange = (r: 0.98, g: 0.65, b: 0.18)
        let green  = (r: 0.22, g: 0.73, b: 0.43)
        if clamped <= 0.10 {
            return lerp(red, orange, t: clamped / 0.10)
        } else {
            return lerp(orange, green, t: (clamped - 0.10) / 0.90)
        }
    }

    private static func lerp(
        _ a: (r: Double, g: Double, b: Double),
        _ b: (r: Double, g: Double, b: Double),
        t: Double
    ) -> Color {
        Color(
            red:   a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue:  a.b + (b.b - a.b) * t
        )
    }
}
