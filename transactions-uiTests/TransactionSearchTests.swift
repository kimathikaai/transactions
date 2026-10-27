import Foundation
import Testing
@testable import transactions_ui

@Suite("Transaction search matching")
struct TransactionSearchTests {

    private func snapshot(
        details: String = "row",
        notes: String? = nil,
        amount: Double = 0
    ) -> TransactionSnapshot {
        let tx = Transaction(
            contentHash: UUID().uuidString,
            date: Date(timeIntervalSince1970: 0),
            details: details,
            debit: amount < 0 ? -amount : 0,
            credit: amount > 0 ? amount : 0,
            transactionType: .expense,
            accountID: UUID()
        )
        return TransactionSnapshot(
            transaction: tx,
            id: tx.id,
            date: tx.date,
            accountID: tx.accountID,
            accountName: "Chequing",
            details: details,
            effectiveType: .expense,
            effectiveCategory: nil,
            effectiveSubcategory: nil,
            effectiveAmount: amount,
            notes: notes,
            isEdited: false,
            isReimbursed: false,
            isUsed: false
        )
    }

    @Test("Empty query matches everything")
    func emptyQueryMatches() {
        #expect(snapshot(details: "Starbucks").matches(searchText: ""))
        #expect(snapshot(details: "Starbucks").matches(searchText: "   "))
    }

    @Test("Matches on details, case-insensitively")
    func detailsMatch() {
        #expect(snapshot(details: "Starbucks").matches(searchText: "star"))
        #expect(!snapshot(details: "Starbucks").matches(searchText: "loblaws"))
    }

    @Test("Matches on notes")
    func notesMatch() {
        let snap = snapshot(details: "Amazon", notes: "birthday refund")
        #expect(snap.matches(searchText: "refund"))
        #expect(!snapshot(details: "Amazon", notes: nil).matches(searchText: "refund"))
    }

    @Test("Matches on plain two-decimal amount, sign-insensitive")
    func amountMatch() {
        let snap = snapshot(details: "Amazon", amount: -45.20)
        #expect(snap.matches(searchText: "45.20"))
        #expect(snap.matches(searchText: "45.2"))
        #expect(snap.matches(searchText: ".20"))
        #expect(!snap.matches(searchText: "45.21"))
    }

    @Test("Multi-term is AND across terms, OR across fields")
    func multiTermAcrossFields() {
        let snap = snapshot(details: "Starbucks", notes: nil, amount: -4.50)
        #expect(snap.matches(searchText: "starbucks 4.50"))   // details + amount
        #expect(!snap.matches(searchText: "starbucks 9.99"))  // amount term misses
        #expect(!snap.matches(searchText: "loblaws 4.50"))    // details term misses
    }
}
