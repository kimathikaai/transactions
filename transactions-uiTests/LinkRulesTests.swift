import Foundation
import Testing
@testable import transactions_ui

@Suite("Link rules")
struct LinkRulesTests {

    private static let accountA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private static let accountB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    /// UTC midnight of 2026-03-<day>.
    private func march(_ day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 3, day: day))!
    }

    private func tx(
        _ hash: String, _ type: TransactionType, _ magnitude: Double, day: Int,
        account: UUID = LinkRulesTests.accountA, edit: TransactionEdit? = nil
    ) -> Transaction {
        let isOut = type == .expense || type == .transfer_out
        return Transaction(
            contentHash: hash, date: march(day), details: "INTERNET TRANSFER",
            debit: isOut ? magnitude : 0, credit: isOut ? 0 : magnitude,
            transactionType: type, accountID: account, edit: edit
        )
    }

    private func pairs(_ txs: [Transaction], blocked: Set<String> = [], excluded: Set<HashPair> = []) -> [HashPair] {
        TransferAutoPairer.pairs(in: txs, blocked: blocked, excludedPairs: excluded)
    }

    // MARK: - Auto-pairer

    @Test func pairsOppositeTransfersAcrossAccounts() {
        let out = tx("out", .transfer_out, 500, day: 1)
        let inn = tx("in", .transfer_in, 500, day: 2, account: Self.accountB)
        #expect(pairs([out, inn]) == [HashPair("out", "in")])
    }

    @Test func threeDayBoundary() {
        let out = tx("out", .transfer_out, 500, day: 1)
        let gap3 = tx("in", .transfer_in, 500, day: 4, account: Self.accountB)
        let gap4 = tx("in", .transfer_in, 500, day: 5, account: Self.accountB)
        #expect(pairs([out, gap3]) == [HashPair("out", "in")])
        #expect(pairs([out, gap4]).isEmpty)
    }

    @Test func requiresDifferentAccounts() {
        let out = tx("out", .transfer_out, 500, day: 1)
        let inn = tx("in", .transfer_in, 500, day: 2)
        #expect(pairs([out, inn]).isEmpty)
    }

    @Test func requiresOppositeDirection() {
        let out1 = tx("out1", .transfer_out, 500, day: 1)
        let out2 = tx("out2", .transfer_out, 500, day: 2, account: Self.accountB)
        #expect(pairs([out1, out2]).isEmpty)
    }

    @Test func ignoresNonTransfers() {
        let expense = tx("exp", .expense, 500, day: 1)
        let income = tx("inc", .income, 500, day: 1, account: Self.accountB)
        #expect(pairs([expense, income]).isEmpty)
    }

    @Test func amountsCompareToTheCent() {
        let out = tx("out", .transfer_out, 0.3, day: 1)
        let inn = tx("in", .transfer_in, 0.1 + 0.2, day: 1, account: Self.accountB)
        #expect(pairs([out, inn]) == [HashPair("out", "in")])

        let out500 = tx("out", .transfer_out, 500.00, day: 1)
        let in501 = tx("in", .transfer_in, 500.01, day: 1, account: Self.accountB)
        #expect(pairs([out500, in501]).isEmpty)
    }

    @Test func greedyPrefersClosestDate() {
        let out1 = tx("out1", .transfer_out, 500, day: 1)
        let out2 = tx("out2", .transfer_out, 500, day: 2)
        let inn = tx("in", .transfer_in, 500, day: 2, account: Self.accountB)
        #expect(pairs([out1, out2, inn]) == [HashPair("out2", "in")])
    }

    @Test func recurringTransfersPairInOrder() {
        let txs = [
            tx("out1", .transfer_out, 100, day: 1),
            tx("out8", .transfer_out, 100, day: 8),
            tx("out15", .transfer_out, 100, day: 15),
            tx("in2", .transfer_in, 100, day: 2, account: Self.accountB),
            tx("in9", .transfer_in, 100, day: 9, account: Self.accountB),
            tx("in16", .transfer_in, 100, day: 16, account: Self.accountB),
        ]
        #expect(Set(pairs(txs)) == [
            HashPair("out1", "in2"), HashPair("out8", "in9"), HashPair("out15", "in16"),
        ])
    }

    @Test func blockedHashesAreSkipped() {
        let out = tx("out", .transfer_out, 500, day: 1)
        let inn = tx("in", .transfer_in, 500, day: 2, account: Self.accountB)
        #expect(pairs([out, inn], blocked: ["out"]).isEmpty)
    }

    @Test func excludedPairsAreSkipped() {
        let out = tx("out", .transfer_out, 500, day: 1)
        let in1 = tx("in1", .transfer_in, 500, day: 1, account: Self.accountB)
        #expect(pairs([out, in1], excluded: [HashPair("out", "in1")]).isEmpty)

        let in2 = tx("in2", .transfer_in, 500, day: 3, account: Self.accountB)
        #expect(pairs([out, in1, in2], excluded: [HashPair("out", "in1")]) == [HashPair("out", "in2")])
    }

    @Test func usesEffectiveType() {
        let retyped = tx("out", .expense, 500, day: 1, edit: TransactionEdit(transactionType: .transfer_out))
        let inn = tx("in", .transfer_in, 500, day: 2, account: Self.accountB)
        #expect(pairs([retyped, inn]) == [HashPair("out", "in")])
    }

    // MARK: - Kind inference

    @Test func inferredKind() {
        let out = tx("out", .transfer_out, 500, day: 1)
        let inB = tx("in", .transfer_in, 500, day: 2, account: Self.accountB)
        let inA = tx("inA", .transfer_in, 500, day: 2)
        let income = tx("inc", .income, 500, day: 2, account: Self.accountB)

        #expect(LinkKind.inferred(out, inB, eitherHasTransferLink: false) == .transfer)
        #expect(LinkKind.inferred(inB, out, eitherHasTransferLink: false) == .transfer)
        #expect(LinkKind.inferred(out, inA, eitherHasTransferLink: false) == .related)
        #expect(LinkKind.inferred(out, inB, eitherHasTransferLink: true) == .related)
        #expect(LinkKind.inferred(income, inB, eitherHasTransferLink: false) == .related)
    }

    @Test func mirroredTypes() {
        #expect(TransactionType.transfer_out.mirrored == .transfer_in)
        #expect(TransactionType.transfer_in.mirrored == .transfer_out)
        #expect(TransactionType.income.mirrored == .income)
        #expect(TransactionType.expense.mirrored == .expense)
    }

    // MARK: - Candidate ranking

    private func snap(_ tx: Transaction) -> TransactionSnapshot {
        TransactionSnapshot(
            transaction: tx, id: tx.contentHash, date: tx.date, accountID: tx.accountID,
            accountName: nil, details: tx.details, effectiveType: tx.effectiveType,
            effectiveCategory: nil, effectiveSubcategory: nil, effectiveAmount: tx.effectiveAmount,
            notes: nil, isEdited: false, isReimbursed: false, isUsed: false
        )
    }

    @Test func rankingPutsSameAmountNearDatesFirst() {
        let source = tx("src", .transfer_out, 500, day: 1)
        // Input order is newest-first, as in transactionsByDateDesc.
        let candidates = [
            tx("500mar20", .transfer_in, 500, day: 20, account: Self.accountB),
            tx("500mar3", .transfer_in, 500, day: 3, account: Self.accountB),
            tx("500mar2", .transfer_in, 500, day: 2, account: Self.accountB),
            tx("20mar1", .expense, 20, day: 1),
        ].map(snap)
        let ranked = LinkCandidates.ranked(for: source, from: candidates, alreadyLinked: [])
        #expect(ranked.map(\.id) == ["500mar2", "500mar3", "500mar20", "20mar1"])
    }

    @Test func rankingExcludesSelfAndAlreadyLinked() {
        let source = tx("src", .transfer_out, 500, day: 1)
        let candidates = [
            source,
            tx("linked", .transfer_in, 500, day: 1, account: Self.accountB),
            tx("other", .income, 10, day: 1),
        ].map(snap)
        let ranked = LinkCandidates.ranked(for: source, from: candidates, alreadyLinked: ["linked"])
        #expect(ranked.map(\.id) == ["other"])
    }

    // MARK: - Create & link defaults

    @Test func defaultDetailsByType() {
        #expect(CreateLinkDefaults.details(for: .transfer_in, sourceAccountName: "Chequing") == "Transfer from Chequing")
        #expect(CreateLinkDefaults.details(for: .transfer_out, sourceAccountName: "Chequing") == "Transfer to Chequing")
        #expect(CreateLinkDefaults.details(for: .income, sourceAccountName: "Chequing") == "")
        #expect(CreateLinkDefaults.details(for: .expense, sourceAccountName: "Chequing") == "")
    }

    @Test func accountChoicesExcludeSourceForTransfers() {
        let accounts = [Self.accountA, Self.accountB, UUID()].enumerated().map { index, id in
            Account(id: id, name: "Account \(index)", type: .chequing, initialBalance: 0, csvFileName: "\(index).csv")
        }
        let transfer = tx("t", .transfer_out, 500, day: 1)
        let income = tx("i", .income, 500, day: 1)
        #expect(CreateLinkDefaults.accountChoices(for: transfer, in: accounts).map(\.id) == [accounts[1].id, accounts[2].id])
        #expect(CreateLinkDefaults.accountChoices(for: income, in: accounts).map(\.id) == accounts.map(\.id))
    }
}
