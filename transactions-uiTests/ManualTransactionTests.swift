import Foundation
import Testing
@testable import transactions_ui

/// Covers manual add/delete of transactions on an account: the sign convention,
/// comma-in-details quoting, input rejection, duplicate handling, and that a
/// delete rewrites the CSV and clears any orphaned edit.
@Suite("Manual add/delete transactions")
struct ManualTransactionTests {

    private func makeVM(dir: TempDataDirectory) -> AppViewModel {
        AppViewModel(
            accountStore: AccountStore(fileURL: dir.file("accounts.json")),
            reserveStore: ReserveStore(fileURL: dir.file("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.file("reserveEvents.json")),
            editStore: EditStore(fileURL: dir.file("edits.json")),
            csvDirectory: dir.url
        )
    }

    private func seedAccount(dir: TempDataDirectory, csvFileName: String) throws -> Account {
        let account = Account(
            id: UUID(),
            name: "Chequing",
            type: .chequing,
            initialBalance: 0,
            csvFileName: csvFileName
        )
        try AtomicJSONFile.save([account], to: dir.file("accounts.json"))
        return account
    }

    private func rows(_ vm: AppViewModel, _ account: Account) -> [Transaction] {
        vm.allTransactions.filter { $0.accountID == account.id }
    }

    @Test("Negative amount becomes an expense; positive becomes income")
    func signConvention() throws {
        let dir = TempDataDirectory(); defer { dir.cleanup() }
        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        let vm = makeVM(dir: dir)

        #expect(vm.addManualTransaction(date: Date(), signedAmount: -50, details: "Coffee", into: account) == true)
        #expect(vm.addManualTransaction(date: Date(), signedAmount: 100, details: "Refund", into: account) == true)

        let all = rows(vm, account)
        #expect(all.count == 2)

        let expense = try #require(all.first { $0.details == "Coffee" })
        #expect(expense.effectiveAmount == -50)
        #expect(expense.transactionType == .expense)

        let income = try #require(all.first { $0.details == "Refund" })
        #expect(income.effectiveAmount == 100)
        #expect(income.transactionType == .income)
    }

    @Test("Commas in details survive via quoting")
    func commaInDetailsSurvives() throws {
        let dir = TempDataDirectory(); defer { dir.cleanup() }
        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        let vm = makeVM(dir: dir)

        #expect(vm.addManualTransaction(date: Date(), signedAmount: -12, details: "Coffee, large tip", into: account) == true)

        let all = rows(vm, account)
        #expect(all.count == 1)
        #expect(all.first?.details == "Coffee, large tip")
        #expect(all.first?.effectiveAmount == -12)
    }

    @Test("Embedded double-quotes are stripped from details")
    func doubleQuotesStripped() throws {
        let dir = TempDataDirectory(); defer { dir.cleanup() }
        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        let vm = makeVM(dir: dir)

        #expect(vm.addManualTransaction(date: Date(), signedAmount: -8, details: "The \"Fancy\" Cafe", into: account) == true)
        #expect(rows(vm, account).first?.details == "The Fancy Cafe")
    }

    @Test("Zero and blank inputs are rejected")
    func rejectsInvalidInput() throws {
        let dir = TempDataDirectory(); defer { dir.cleanup() }
        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        let vm = makeVM(dir: dir)

        #expect(vm.addManualTransaction(date: Date(), signedAmount: 0, details: "Nope", into: account) == false)
        #expect(vm.addManualTransaction(date: Date(), signedAmount: -5, details: "   ", into: account) == false)
        #expect(rows(vm, account).isEmpty)
    }

    @Test("Two identical adds produce two distinct rows")
    func duplicateAddsAreDistinct() throws {
        let dir = TempDataDirectory(); defer { dir.cleanup() }
        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        let vm = makeVM(dir: dir)

        let day = Date()
        #expect(vm.addManualTransaction(date: day, signedAmount: -5, details: "Coffee", into: account) == true)
        #expect(vm.addManualTransaction(date: day, signedAmount: -5, details: "Coffee", into: account) == true)

        let all = rows(vm, account)
        #expect(all.count == 2)
        #expect(Set(all.map(\.contentHash)).count == 2)   // distinct hashes via occurrence index
    }

    @Test("Delete removes exactly one row and rewrites the CSV")
    func deleteRemovesOneRow() throws {
        let dir = TempDataDirectory(); defer { dir.cleanup() }
        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        try """
        2026-05-01,COFFEE SHOP,4.50,
        2026-05-02,PAYCHECK,,2000.00
        """.write(to: dir.file("chq.csv"), atomically: true, encoding: .utf8)

        let vm = makeVM(dir: dir)
        #expect(rows(vm, account).count == 2)

        let target = try #require(rows(vm, account).first { $0.details == "COFFEE SHOP" })
        #expect(vm.deleteTransaction(target, from: account) == true)

        let after = rows(vm, account)
        #expect(after.count == 1)
        #expect(after.first?.details == "PAYCHECK")

        let onDisk = try String(contentsOf: dir.file("chq.csv"), encoding: .utf8)
        #expect(!onDisk.contains("COFFEE SHOP"))
        #expect(onDisk.contains("2026-05-02,PAYCHECK,,2000.00"))
    }

    @Test("Deleting one of two identical rows leaves exactly one")
    func deleteDuplicateLeavesOne() throws {
        let dir = TempDataDirectory(); defer { dir.cleanup() }
        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        let vm = makeVM(dir: dir)

        let day = Date()
        vm.addManualTransaction(date: day, signedAmount: -5, details: "Coffee", into: account)
        vm.addManualTransaction(date: day, signedAmount: -5, details: "Coffee", into: account)
        #expect(rows(vm, account).count == 2)

        let target = try #require(rows(vm, account).first)
        #expect(vm.deleteTransaction(target, from: account) == true)
        #expect(rows(vm, account).count == 1)
    }

    @Test("Deleting a row clears its orphaned edit")
    func deleteClearsOrphanedEdit() throws {
        let dir = TempDataDirectory(); defer { dir.cleanup() }
        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        let vm = makeVM(dir: dir)

        #expect(vm.addManualTransaction(date: Date(), signedAmount: -20, details: "Lunch", into: account) == true)
        let target = try #require(rows(vm, account).first)
        let hash = target.contentHash
        #expect(vm.saveEdit(for: target, category: CategoryID(rawValue: "food"), subcategory: nil, notes: "team lunch") == true)

        #expect(vm.deleteTransaction(target, from: account) == true)
        #expect(rows(vm, account).isEmpty)

        // The edit should no longer be on disk.
        let reloaded = EditStore(fileURL: dir.file("edits.json"))
        try reloaded.load()
        #expect(reloaded.edits[hash] == nil)
    }
}
