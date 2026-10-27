import Foundation

// Shared CAD currency formatting. One source of truth so views don't hand-roll
// NumberFormatters or repeat `.currency(code: "CAD")` inline.
//
// Usable both as a `format:` argument and via `.formatted(_:)`:
//   Text(value, format: .cad)
//   value.formatted(.cadWhole)
extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Currency {
    /// CAD with cents (e.g. $1,234.00).
    static var cad: Self { .currency(code: "CAD") }

    /// CAD rounded to whole dollars (e.g. $1,234) — for dense contexts like
    /// chart axes and tooltips.
    static var cadWhole: Self { .currency(code: "CAD").precision(.fractionLength(0)) }
}
