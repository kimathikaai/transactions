import Foundation
import Testing
@testable import transactions_ui

@Suite("ReserveStore")
struct ReserveStoreTests {

    private func sample() -> Reserve {
        Reserve(
            id: UUID(), name: "Emergency", emoji: "🚨", colorHex: "#F00",
            target: 5000, tagline: "", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            sortOrder: 0
        )
    }

    @Test func loadOnMissingFileYieldsEmpty() throws {
        let dir = TempDataDirectory()
        let store = ReserveStore(fileURL: dir.file("reserves.json"))
        try store.load()
        #expect(store.reserves.isEmpty)
    }

    @Test func upsertPersists() throws {
        let dir = TempDataDirectory()
        let store = ReserveStore(fileURL: dir.file("reserves.json"))
        let record = sample()
        try store.upsert(record)

        let fresh = ReserveStore(fileURL: dir.file("reserves.json"))
        try fresh.load()
        #expect(fresh.reserves == [record])
    }

    @Test func deleteRemovesRecord() throws {
        let dir = TempDataDirectory()
        let store = ReserveStore(fileURL: dir.file("reserves.json"))
        let record = sample()
        try store.upsert(record)
        try store.delete(id: record.id)
        #expect(store.reserves.isEmpty)
    }
}
