import Foundation
import Testing
@testable import transactions_ui

/// The shared signed amount: a paycheque and an equal expense must differ.
@Suite("Transaction snapshot amount")
struct TransactionSnapshotAmountTests {

    private func snapshot(type: TransactionType, amount: Double) -> TransactionSnapshot {
        let tx = Transaction(
            contentHash: UUID().uuidString,
            date: Date(timeIntervalSince1970: 0),
            details: "GLOBEX CORP",
            debit: amount < 0 ? -amount : 0,
            credit: amount > 0 ? amount : 0,
            transactionType: type,
            accountID: UUID()
        )
        return TransactionSnapshot(
            transaction: tx, id: tx.id, date: tx.date, accountID: tx.accountID,
            accountName: "Chequing", details: tx.details, effectiveType: type,
            effectiveCategory: nil, effectiveSubcategory: nil, effectiveAmount: amount,
            notes: nil, isEdited: false, isReimbursed: false, isUsed: false
        )
    }

    @Test func inflowsAreUnsigned() {
        #expect(snapshot(type: .income, amount: 2_000).signedAmountText == 2_000.0.formatted(.cad))
        #expect(snapshot(type: .transfer_in, amount: 50).signedAmountText == 50.0.formatted(.cad))
    }

    @Test func outflowsCarryAMinus() {
        #expect(snapshot(type: .expense, amount: -2_000).signedAmountText == "-" + 2_000.0.formatted(.cad))
        #expect(snapshot(type: .transfer_out, amount: -50).signedAmountText == "-" + 50.0.formatted(.cad))
    }
}
