import Foundation

extension FormatStyle where Self == Date.VerbatimFormatStyle {
    /// `MMM-YY`, e.g. `Jan-24`. Cached because building a format style is not free.
    static var monthYear: Self { Self.cachedMonthYear }
}

extension Date.VerbatimFormatStyle {
    fileprivate static let cachedMonthYear: Date.VerbatimFormatStyle = .verbatim(
        "\(month: .abbreviated)-\(year: .twoDigits)",
        timeZone: .current,
        calendar: .current
    )
}
