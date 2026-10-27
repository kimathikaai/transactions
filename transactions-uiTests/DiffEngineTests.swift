import Foundation
import Testing
@testable import transactions_ui

struct DiffEngineTests {

    private func tx(accountID: UUID, hashSeed: String, date: Date = Date()) -> Transaction {
        Transaction(
            contentHash: hashSeed,
            date: date,
            details: hashSeed,
            debit: 0,
            credit: 0,
            transactionType: .expense,
            accountID: accountID
        )
    }

    @Test("Identical sets diff to empty")
    func idempotent() throws {
        let aid = UUID()
        let existing = [tx(accountID: aid, hashSeed: "a"), tx(accountID: aid, hashSeed: "b")]
        let incoming = [tx(accountID: aid, hashSeed: "a"), tx(accountID: aid, hashSeed: "b")]
        let diff = DiffEngine.diff(existing: existing, incoming: incoming)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.isEmpty)
    }

    @Test("Truncated incoming yields only removed")
    func truncated() throws {
        let aid = UUID()
        let existing = [tx(accountID: aid, hashSeed: "a"), tx(accountID: aid, hashSeed: "b"), tx(accountID: aid, hashSeed: "c")]
        let incoming = [tx(accountID: aid, hashSeed: "a")]
        let diff = DiffEngine.diff(existing: existing, incoming: incoming)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.map(\.contentHash).sorted() == ["b", "c"])
    }

    @Test("Extended incoming yields only added")
    func extended() throws {
        let aid = UUID()
        let existing = [tx(accountID: aid, hashSeed: "a")]
        let incoming = [tx(accountID: aid, hashSeed: "a"), tx(accountID: aid, hashSeed: "b"), tx(accountID: aid, hashSeed: "c")]
        let diff = DiffEngine.diff(existing: existing, incoming: incoming)
        #expect(diff.added.map(\.contentHash).sorted() == ["b", "c"])
        #expect(diff.removed.isEmpty)
    }

    @Test("Mixed change yields both added and removed")
    func mixed() throws {
        let aid = UUID()
        let existing = [tx(accountID: aid, hashSeed: "a"), tx(accountID: aid, hashSeed: "b")]
        let incoming = [tx(accountID: aid, hashSeed: "b"), tx(accountID: aid, hashSeed: "c")]
        let diff = DiffEngine.diff(existing: existing, incoming: incoming)
        #expect(diff.added.map(\.contentHash) == ["c"])
        #expect(diff.removed.map(\.contentHash) == ["a"])
    }
}
