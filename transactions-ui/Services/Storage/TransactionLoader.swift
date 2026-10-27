import Foundation

/// Reads per-account CSVs off disk, runs them through `BankCsvParser` +
/// `ImportPipeline`, and stitches user edits from `edits.json` onto the
/// resulting transactions. Used at startup (`loadAll`) and after a CSV
/// upload commit (`loadOne`).
enum TransactionLoader {

    struct AccountLoadResult {
        let accountID: UUID
        let transactions: [Transaction]
        let error: Error?
    }

    static func loadAll(
        accounts: [Account],
        csvDirectory: URL,
        transferKeywords: [String],
        categories: [Category]
    ) -> [AccountLoadResult] {
        accounts.map { acct in
            loadOne(
                account: acct,
                csvDirectory: csvDirectory,
                transferKeywords: transferKeywords,
                categories: categories
            )
        }
    }

    static func loadOne(
        account: Account,
        csvDirectory: URL,
        transferKeywords: [String],
        categories: [Category]
    ) -> AccountLoadResult {
        let url = csvDirectory.appendingPathComponent(account.csvFileName)
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            let parsed = try BankCsvParser.parse(csvString: raw)
            let rows = parsed.map { $0.row }
            let txs = ImportPipeline.makeTransactions(
                from: rows,
                accountID: account.id,
                transferKeywords: transferKeywords,
                categories: categories
            )
            return AccountLoadResult(accountID: account.id, transactions: txs, error: nil)
        } catch {
            return AccountLoadResult(accountID: account.id, transactions: [], error: error)
        }
    }

    /// Attaches `TransactionEdit` values onto matching transactions by
    /// `contentHash`. Transactions with no edit are left untouched.
    static func applyEdits(
        _ edits: [String: TransactionEdit],
        to transactions: inout [Transaction]
    ) {
        for i in transactions.indices {
            if let edit = edits[transactions[i].contentHash] {
                transactions[i].edit = edit
            }
        }
    }
}
