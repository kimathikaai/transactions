import Foundation

/// Stateless transaction builder. Turns parsed bank rows into value-typed
/// `Transaction` structs. Every launch, `AppViewModel` calls this once per
/// account with the parsed CSV rows; there is no persistence pass anymore.
///
/// - debit > 0 → expense (negative amount); else income (positive)
/// - rows whose details match a transfer keyword get reclassified as
///   transfer_in/_out by sign; the resulting category id is resolved from
///   the catalog (first root matching the transfer type). Missing transfer
///   root → category left nil.
/// - non-transfers are categorized by the first matching regex derived from
///   the catalog's leaves (case-insensitive). No match → nil category.
enum ImportPipeline {

    static func makeTransactions(
        from rows: [BankRow],
        accountID: UUID,
        transferKeywords: [String],
        categories: [Category]
    ) -> [Transaction] {
        let uppercasedKeywords = transferKeywords.map { $0.uppercased() }

        let derivedRules = CategoryLookup.rules(from: categories)
        let compiledRules: [(txType: TransactionType, category: CategoryID, subcategory: SubcategoryID, regex: NSRegularExpression)] =
            derivedRules.compactMap { rule in
                guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive)
                else { return nil }
                return (rule.txType, rule.category, rule.subcategory, regex)
            }

        let transferInID  = CategoryLookup.firstRoot(ofType: .transfer_in,  in: categories).map { CategoryID(rawValue: $0.id) }
        let transferOutID = CategoryLookup.firstRoot(ofType: .transfer_out, in: categories).map { CategoryID(rawValue: $0.id) }

        // Walk rows in CSV order, assigning per-row-content occurrence indices.
        // Two byte-identical rows in the same CSV (e.g. two $5 coffees on the
        // same day) get indices 0, 1, … so their hashes are distinct.
        var occurrenceCounts: [String: Int] = [:]

        return rows.map { row in
            let baseType: TransactionType = row.debit > 0 ? .expense : .income

            let occurrenceKey = "\(row.date.timeIntervalSinceReferenceDate)|\(row.details)|\(row.debit)|\(row.credit)"
            let occurrenceIndex = occurrenceCounts[occurrenceKey, default: 0]
            occurrenceCounts[occurrenceKey] = occurrenceIndex + 1

            let hash = ContentHasher.hash(
                accountID: accountID,
                date: row.date,
                details: row.details,
                debit: row.debit,
                credit: row.credit,
                occurrenceIndex: occurrenceIndex
            )

            let descUpper = row.details.uppercased()
            let isTransfer = uppercasedKeywords.contains { descUpper.contains($0) }
            if isTransfer {
                let signedAmount = row.credit - row.debit
                let direction: TransactionType = signedAmount > 0 ? .transfer_in : .transfer_out
                return Transaction(
                    contentHash: hash,
                    date: row.date,
                    details: row.details,
                    debit: row.debit,
                    credit: row.credit,
                    transactionType: direction,
                    category: direction == .transfer_in ? transferInID : transferOutID,
                    accountID: accountID
                )
            }

            let range = NSRange(row.details.startIndex..., in: row.details)
            for rule in compiledRules {
                if rule.txType != baseType { continue }
                if rule.regex.firstMatch(in: row.details, range: range) != nil {
                    return Transaction(
                        contentHash: hash,
                        date: row.date,
                        details: row.details,
                        debit: row.debit,
                        credit: row.credit,
                        transactionType: baseType,
                        category: rule.category,
                        subcategory: rule.subcategory,
                        accountID: accountID
                    )
                }
            }

            return Transaction(
                contentHash: hash,
                date: row.date,
                details: row.details,
                debit: row.debit,
                credit: row.credit,
                transactionType: baseType,
                category: nil,
                subcategory: nil,
                accountID: accountID
            )
        }
    }
}
