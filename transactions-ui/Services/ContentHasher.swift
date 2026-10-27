import CryptoKit
import Foundation

/// Deterministic content hash for a single transaction. Same inputs → same hash forever.
/// The result is the first 6 bytes (12 hex chars) of SHA-256 over a canonical string.
///
/// `occurrenceIndex` disambiguates byte-identical rows within the same CSV (e.g. two
/// $5 coffees at the same shop on the same day). Within a single import, the Nth
/// occurrence of a `(date, details, debit, credit)` tuple is given index N. As long as
/// the bank exports rows in a deterministic order, re-uploading the same CSV reproduces
/// the same indices and therefore the same hashes — diffing remains a no-op.
///
/// WARNING: any change to the canonical string format rewrites every transaction's
/// content hash and orphans existing TransactionEdit rows. Migrate first if you must.
///
/// WARNING: hashes are stable only **within a single install**. The accountID is a
/// per-install UUID (a fresh `Account` is created on every onboarding), so the same
/// CSV row reproduced on a different install yields a different hash. Do not rely on
/// content hashes for cross-install identity, sync, or device migration — those flows
/// need an export/import path that re-keys edits by their (account, row) pair.
enum ContentHasher {

    /// Canonical date format. Mirrors pandas Timestamp f-string repr (`"YYYY-MM-DD HH:mm:ss"`)
    /// in UTC POSIX so hashes are reproducible regardless of locale or timezone.
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    static func hash(
        accountID: UUID,
        date: Date,
        details: String,
        debit: Double,
        credit: Double,
        occurrenceIndex: Int
    ) -> String {
        let raw = [
            accountID.uuidString,
            dateFormatter.string(from: date),
            details,
            "\(debit)",
            "\(credit)",
            "\(occurrenceIndex)",
        ].joined(separator: " ")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
