import Foundation
import Testing
@testable import transactions_ui

struct CategoryStoreTests {

    private func tempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("categories.json")
    }

    private func sample(_ name: String, id: String, parent: String? = nil) -> transactions_ui.Category {
        transactions_ui.Category(id: id, displayName: name, parent: parent,
                 color: "#8dd3c7", symbol: "folder",
                 transactionType: .expense, patterns: [])
    }

    @Test("Missing file loads as empty array")
    func loadMissingFile() throws {
        let store = CategoryStore(fileURL: tempURL())
        try store.load()
        #expect(store.categories.isEmpty)
    }

    @Test("Upsert then load round-trips")
    func upsertRoundTrip() throws {
        let url = tempURL()
        let a = CategoryStore(fileURL: url)
        try a.load()
        try a.upsert(sample("Food", id: "cat_1"))
        try a.upsert(sample("Groceries", id: "cat_2", parent: "cat_1"))

        let b = CategoryStore(fileURL: url)
        try b.load()
        #expect(b.categories.count == 2)
        #expect(b.categories.first?.displayName == "Food")
        #expect(b.categories.last?.parent == "cat_1")
    }

    @Test("Upsert replaces by id, preserving order")
    func upsertReplaces() throws {
        let store = CategoryStore(fileURL: tempURL())
        try store.load()
        try store.upsert(sample("Food", id: "cat_1"))
        try store.upsert(sample("Transport", id: "cat_2"))
        var updated = store.categories[0]
        updated.displayName = "Food & Drink"
        try store.upsert(updated)
        #expect(store.categories.count == 2)
        #expect(store.categories[0].displayName == "Food & Drink")
        #expect(store.categories[1].displayName == "Transport")
    }

    @Test("Delete by id is a no-op when missing")
    func deleteMissing() throws {
        let store = CategoryStore(fileURL: tempURL())
        try store.load()
        try store.upsert(sample("Food", id: "cat_1"))
        try store.delete(id: "cat_missing")
        #expect(store.categories.count == 1)
        try store.delete(id: "cat_1")
        #expect(store.categories.isEmpty)
    }

    @Test("ReplaceAll rewrites the whole file")
    func replaceAll() throws {
        let url = tempURL()
        let store = CategoryStore(fileURL: url)
        try store.load()
        try store.upsert(sample("Food", id: "cat_1"))
        try store.replaceAll([sample("Transport", id: "cat_2")])
        let fresh = CategoryStore(fileURL: url)
        try fresh.load()
        #expect(fresh.categories.map(\.id) == ["cat_2"])
    }
}
