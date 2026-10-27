import Foundation
import Testing
@testable import transactions_ui

struct ContentHasherTests {

    private func date(_ s: String) -> Date {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: s)!
    }

    @Test("Same inputs produce the same hash")
    func deterministic() {
        let id = UUID()
        let h1 = ContentHasher.hash(accountID: id, date: date("2025-01-10"),
                                    details: "STARBUCKS", debit: 5.50, credit: 0,
                                    occurrenceIndex: 0)
        let h2 = ContentHasher.hash(accountID: id, date: date("2025-01-10"),
                                    details: "STARBUCKS", debit: 5.50, credit: 0,
                                    occurrenceIndex: 0)
        #expect(h1 == h2)
    }

    @Test("Hash is 12 hex characters")
    func length() {
        let h = ContentHasher.hash(accountID: UUID(), date: date("2025-01-10"),
                                   details: "X", debit: 1, credit: 0,
                                   occurrenceIndex: 0)
        #expect(h.count == 12)
        #expect(h.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test("Different accountIDs produce different hashes")
    func accountIDChangesHash() {
        let h1 = ContentHasher.hash(accountID: UUID(), date: date("2025-01-10"),
                                    details: "X", debit: 1, credit: 0,
                                    occurrenceIndex: 0)
        let h2 = ContentHasher.hash(accountID: UUID(), date: date("2025-01-10"),
                                    details: "X", debit: 1, credit: 0,
                                    occurrenceIndex: 0)
        #expect(h1 != h2)
    }

    @Test("Different details produce different hashes")
    func detailsChangesHash() {
        let id = UUID()
        let h1 = ContentHasher.hash(accountID: id, date: date("2025-01-10"),
                                    details: "FOO", debit: 1, credit: 0,
                                    occurrenceIndex: 0)
        let h2 = ContentHasher.hash(accountID: id, date: date("2025-01-10"),
                                    details: "BAR", debit: 1, credit: 0,
                                    occurrenceIndex: 0)
        #expect(h1 != h2)
    }

    @Test("Different amounts produce different hashes")
    func amountChangesHash() {
        let id = UUID()
        let h1 = ContentHasher.hash(accountID: id, date: date("2025-01-10"),
                                    details: "X", debit: 1.0, credit: 0,
                                    occurrenceIndex: 0)
        let h2 = ContentHasher.hash(accountID: id, date: date("2025-01-10"),
                                    details: "X", debit: 2.0, credit: 0,
                                    occurrenceIndex: 0)
        #expect(h1 != h2)
    }

    @Test("Different occurrenceIndex produces different hashes")
    func occurrenceIndexChangesHash() {
        let id = UUID()
        let h1 = ContentHasher.hash(accountID: id, date: date("2025-01-10"),
                                    details: "STARBUCKS", debit: 5.50, credit: 0,
                                    occurrenceIndex: 0)
        let h2 = ContentHasher.hash(accountID: id, date: date("2025-01-10"),
                                    details: "STARBUCKS", debit: 5.50, credit: 0,
                                    occurrenceIndex: 1)
        #expect(h1 != h2)
    }
}
