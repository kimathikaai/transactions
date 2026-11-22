import Foundation
import Testing
@testable import transactions_ui

@Suite("ReimbursementStore")
struct ReimbursementStoreTests {

    private func sample() -> ReimbursementLink {
        ReimbursementLink(
            reimbursementHash: "income-1",
            amount: 30,
            linkedAt: Date(timeIntervalSince1970: 1_700_000_000),
            note: "work trip"
        )
    }

    private func link(_ income: String, _ amount: Double) -> ReimbursementLink {
        ReimbursementLink(reimbursementHash: income, amount: amount,
                          linkedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func addPersists() throws {
        let dir = TempDataDirectory()
        let store = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try store.add(expenseHash: "expense-a", record: sample())

        let fresh = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try fresh.load()
        #expect(fresh.links["expense-a"] == [sample()])
    }

    @Test func addAppendsASecondIncomeToTheSameExpense() throws {
        let dir = TempDataDirectory()
        let store = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try store.add(expenseHash: "expense-a", record: link("income-1", 40))
        try store.add(expenseHash: "expense-a", record: link("income-2", 50))
        #expect(store.links["expense-a"]?.map(\.reimbursementHash) == ["income-1", "income-2"])
    }

    @Test func deleteRemovesOnlyThatPair() throws {
        let dir = TempDataDirectory()
        let store = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try store.add(expenseHash: "expense-a", record: link("income-1", 40))
        try store.add(expenseHash: "expense-a", record: link("income-2", 50))
        try store.delete(expenseHash: "expense-a", incomeHash: "income-1")
        #expect(store.links["expense-a"]?.map(\.reimbursementHash) == ["income-2"])
    }

    @Test func deletingTheLastLinkDropsTheExpense() throws {
        let dir = TempDataDirectory()
        let store = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try store.add(expenseHash: "expense-a", record: sample())
        try store.delete(expenseHash: "expense-a", incomeHash: "income-1")
        #expect(store.links.isEmpty)
    }

    @Test func loadReadsTheLegacySingleLinkFormat() throws {
        let dir = TempDataDirectory()
        try AtomicJSONFile.save(["expense-a": sample()], to: dir.file("reimbursements.json"))
        let store = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try store.load()
        #expect(store.links["expense-a"] == [sample()])
    }

    @Test func loadMissingFileIsEmpty() throws {
        let dir = TempDataDirectory()
        let store = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try store.load()
        #expect(store.links.isEmpty)
    }

    @Test func replaceAllOverwrites() throws {
        let dir = TempDataDirectory()
        let store = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try store.add(expenseHash: "expense-a", record: sample())
        try store.replaceAll(["expense-b": [sample()]])
        #expect(store.links.count == 1)
        #expect(store.links["expense-b"] == [sample()])
        #expect(store.links["expense-a"] == nil)
    }
}
