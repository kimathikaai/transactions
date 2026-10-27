import Foundation
import Testing
@testable import transactions_ui

@Suite("Transaction.effectiveAmount")
struct TransactionEffectiveAmountTests {

    /// An expense (parsed negative) re-typed to income via an edit yields a
    /// positive effectiveAmount — the sign follows the effective type so aggregate
    /// sums stay consistent after a type change (amount itself is not editable).
    @Test func typeOverrideFlipsSign() {
        var tx = Transaction(
            contentHash: "hash",
            date: Date(timeIntervalSince1970: 0),
            details: "REFUND", debit: 75.00, credit: 0,
            transactionType: .expense, accountID: UUID()
        )
        #expect(tx.amount == -75.00)
        #expect(tx.effectiveAmount == -75.00)

        tx.edit = TransactionEdit(transactionType: .income)
        #expect(tx.effectiveType == .income)
        #expect(tx.effectiveAmount == 75.00)
    }

    /// Without an edit, effectiveAmount matches the parsed signed amount.
    @Test func noEditMatchesParsedAmount() {
        let tx = Transaction(
            contentHash: "hash",
            date: Date(timeIntervalSince1970: 0),
            details: "GROCERIES", debit: 42.00, credit: 0,
            transactionType: .expense, accountID: UUID()
        )
        #expect(tx.effectiveAmount == tx.amount)
        #expect(tx.effectiveAmount == -42.00)
    }
}
