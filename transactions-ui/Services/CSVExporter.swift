import Foundation

enum CSVExporter {
    private static let header: [String] = [
        "content_hash",
        "date",
        "account_id",
        "account_name",
        "type",
        "type_display",
        "details",
        "amount",
        "category",
        "category_display",
        "subcategory",
        "subcategory_display",
        "notes",
    ]

    /// Formatter for transaction dates. Transaction `Date`s originate from
    /// BankCsvParser anchored at 00:00 UTC — format in UTC so a 2026-06-29
    /// CSV row round-trips to 2026-06-29 on export.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Formatter for the "when the user hit Export" wall-clock timestamp in
    /// filenames. This is a real point-in-time and should render in the
    /// user's local timezone (an export at 11pm should not name itself the
    /// next day's file).
    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func makeCSV(from snapshots: [TransactionSnapshot], categories: [Category] = []) -> String {
        let catByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var lines: [String] = []
        lines.reserveCapacity(snapshots.count + 1)
        lines.append(header.map(escape).joined(separator: ","))

        for snap in snapshots {
            let tx = snap.transaction
            let categoryDisplay = tx.effectiveCategory.flatMap { catByID[$0.rawValue]?.displayName } ?? tx.effectiveCategory?.rawValue ?? ""
            let subcategoryDisplay = tx.effectiveSubcategory.flatMap { catByID[$0.rawValue]?.displayName } ?? tx.effectiveSubcategory?.rawValue ?? ""
            let fields: [String] = [
                tx.contentHash,
                dateFormatter.string(from: tx.date),
                snap.accountID?.uuidString ?? "",
                snap.accountName ?? "",
                tx.transactionType.rawValue,
                tx.transactionType.displayName,
                tx.details,
                String(format: "%.2f", tx.amount),
                tx.effectiveCategory?.rawValue ?? "",
                categoryDisplay,
                tx.effectiveSubcategory?.rawValue ?? "",
                subcategoryDisplay,
                tx.effectiveNotes ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func suggestedFilename(now: Date = Date()) -> String {
        "transactions_\(filenameDateFormatter.string(from: now)).csv"
    }

    private nonisolated static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        guard needsQuoting else { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
