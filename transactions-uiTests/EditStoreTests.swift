import Foundation
import Testing
@testable import transactions_ui

@Suite("EditStore")
struct EditStoreTests {

    private func sample() -> TransactionEdit {
        TransactionEdit(category: CategoryID(rawValue: "transport"), subcategory: nil, notes: "cab",
                   transactionType: nil,
                   updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func upsertPersists() throws {
        let dir = TempDataDirectory()
        let store = EditStore(fileURL: dir.file("edits.json"))
        try store.upsert(contentHash: "abc", record: sample())

        let fresh = EditStore(fileURL: dir.file("edits.json"))
        try fresh.load()
        #expect(fresh.edits["abc"] == sample())
    }

    @Test func deleteRemoves() throws {
        let dir = TempDataDirectory()
        let store = EditStore(fileURL: dir.file("edits.json"))
        try store.upsert(contentHash: "abc", record: sample())
        try store.delete(contentHash: "abc")
        #expect(store.edits.isEmpty)
    }
}
