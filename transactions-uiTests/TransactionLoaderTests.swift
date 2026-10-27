import Foundation
import Testing
@testable import transactions_ui

@Suite("TransactionLoader")
struct TransactionLoaderTests {

    private func sampleAccount(_ name: String, csv: String) -> Account {
        Account(id: UUID(), name: name, type: .chequing, initialBalance: 0, csvFileName: csv)
    }

    @Test func loadOneReturnsErrorForMissingFile() {
        let acct = sampleAccount("Missing", csv: "does_not_exist.csv")
        let result = TransactionLoader.loadOne(
            account: acct,
            csvDirectory: FileManager.default.temporaryDirectory,
            transferKeywords: [],
            categories: []
        )
        #expect(result.transactions.isEmpty)
        #expect(result.error != nil)
    }

    @Test func loadOneParsesRealCsv() throws {
        let dir = TempDataDirectory()
        let csvName = "sample.csv"
        let csv = """
        Date,Details,Debit,Credit
        2025-01-01,Coffee,5.00,0
        2025-01-02,Payday,0,1000
        """
        try csv.write(to: dir.file(csvName), atomically: true, encoding: .utf8)

        let acct = sampleAccount("Sample", csv: csvName)
        let result = TransactionLoader.loadOne(
            account: acct,
            csvDirectory: dir.url,
            transferKeywords: [],
            categories: []
        )
        #expect(result.error == nil)
        #expect(result.transactions.count == 2)
        #expect(result.transactions.allSatisfy { $0.accountID == acct.id })
    }

    @Test func applyEditsStitchesByContentHash() {
        let acctID = UUID()
        let tx = Transaction(
            contentHash: "abc123", date: Date(timeIntervalSince1970: 0),
            details: "Test", debit: 10, credit: 0,
            transactionType: .expense, accountID: acctID
        )
        var txs = [tx]
        let edits: [String: TransactionEdit] = [
            "abc123": TransactionEdit(
                category: CategoryID(rawValue: "food"),
                notes: "coffee",
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        ]
        TransactionLoader.applyEdits(edits, to: &txs)
        #expect(txs[0].edit != nil)
        #expect(txs[0].effectiveCategory?.rawValue == "food")
        #expect(txs[0].effectiveNotes == "coffee")
    }
}
