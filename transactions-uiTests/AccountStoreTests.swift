import Foundation
import Testing
@testable import transactions_ui

@Suite("AccountStore")
struct AccountStoreTests {

    private func make() -> (AccountStore, TempDataDirectory) {
        let dir = TempDataDirectory()
        return (AccountStore(fileURL: dir.file("accounts.json")), dir)
    }

    private func sample(_ name: String = "Chequing") -> Account {
        Account(id: UUID(), name: name, type: .chequing,
                      initialBalance: 0, csvFileName: "\(name.lowercased()).csv")
    }

    @Test func loadOnMissingFileYieldsEmpty() throws {
        let (store, _) = make()
        try store.load()
        #expect(store.accounts.isEmpty)
    }

    @Test func upsertInsertsThenPersists() throws {
        let (store, dir) = make()
        let record = sample()
        try store.upsert(record)
        #expect(store.accounts == [record])

        // A fresh store reading the same file sees the same data.
        let fresh = AccountStore(fileURL: dir.file("accounts.json"))
        try fresh.load()
        #expect(fresh.accounts == [record])
    }

    @Test func upsertUpdatesExisting() throws {
        let (store, _) = make()
        var record = sample("A")
        try store.upsert(record)
        record.name = "Renamed"
        try store.upsert(record)
        #expect(store.accounts.count == 1)
        #expect(store.accounts[0].name == "Renamed")
    }

    @Test func deleteRemovesRecord() throws {
        let (store, _) = make()
        let record = sample()
        try store.upsert(record)
        try store.delete(id: record.id)
        #expect(store.accounts.isEmpty)
    }
}
