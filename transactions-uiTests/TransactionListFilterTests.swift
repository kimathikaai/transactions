import Foundation
import Testing
@testable import transactions_ui

@Suite("Transaction list filters")
struct TransactionListFilterTests {

    private func snap(isLinked: Bool) -> TransactionSnapshot {
        let tx = Transaction(
            contentHash: "h", date: Date(timeIntervalSince1970: 0), details: "INTERNET TRANSFER",
            debit: 500, credit: 0, transactionType: .transfer_out, accountID: UUID()
        )
        return TransactionSnapshot(
            transaction: tx, id: tx.contentHash, date: tx.date, accountID: tx.accountID,
            accountName: nil, details: tx.details, effectiveType: tx.effectiveType,
            effectiveCategory: nil, effectiveSubcategory: nil, effectiveAmount: tx.effectiveAmount,
            notes: nil, isEdited: false, isReimbursed: false, isUsed: false, isLinked: isLinked
        )
    }

    @Test func transfersTypeFilterMatchesBothDirections() {
        #expect(TypeFilter.transfers.matches(.transfer_in))
        #expect(TypeFilter.transfers.matches(.transfer_out))
        #expect(!TypeFilter.transfers.matches(.income))
        #expect(!TypeFilter.transfers.matches(.expense))
    }

    @Test func onlyTypeFilterMatchesExactly() {
        #expect(TypeFilter.only(.income).matches(.income))
        #expect(!TypeFilter.only(.income).matches(.expense))
        #expect(!TypeFilter.only(.transfer_in).matches(.transfer_out))
        #expect(TypeFilter.any.matches(.expense))
    }

    @Test func linkFilterMatches() {
        let linked = snap(isLinked: true)
        let unlinked = snap(isLinked: false)
        #expect(LinkFilter.linked.matches(linked))
        #expect(!LinkFilter.linked.matches(unlinked))
        #expect(LinkFilter.unlinked.matches(unlinked))
        #expect(!LinkFilter.unlinked.matches(linked))
        #expect(LinkFilter.all.matches(linked))
        #expect(LinkFilter.all.matches(unlinked))
    }
}
