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

    @Test func upsertPersists() throws {
        let dir = TempDataDirectory()
        let store = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try store.upsert(expenseHash: "expense-a", record: sample())

        let fresh = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try fresh.load()
        #expect(fresh.links["expense-a"] == sample())
    }

    @Test func deleteRemoves() throws {
        let dir = TempDataDirectory()
        let store = ReimbursementStore(fileURL: dir.file("reimbursements.json"))
        try store.upsert(expenseHash: "expense-a", record: sample())
        try store.delete(expenseHash: "expense-a")
        #expect(store.links.isEmpty)
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
        try store.upsert(expenseHash: "expense-a", record: sample())
        try store.replaceAll(["expense-b": sample()])
        #expect(store.links.count == 1)
        #expect(store.links["expense-b"] == sample())
        #expect(store.links["expense-a"] == nil)
    }
}
