import Foundation
import Testing
@testable import transactions_ui

@Suite("Link store")
struct LinkStoreTests {

    private func link(_ x: String, _ y: String, kind: LinkKind = .related, note: String? = nil) -> TransactionLink {
        TransactionLink(
            pair: HashPair(x, y), kind: kind, note: note,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func hashPairIsOrderIndependent() {
        #expect(HashPair("b", "a") == HashPair("a", "b"))
        #expect(HashPair("b", "a").a == "a")
        #expect(HashPair("a", "b").other(than: "a") == "b")
    }

    @Test func missingFileLoadsEmpty() throws {
        let dir = TempDataDirectory()
        let store = LinkStore(fileURL: dir.file("links.json"))
        try store.load()
        #expect(store.links.isEmpty)
        #expect(store.rejections.isEmpty)
    }

    @Test func linksAndRejectionsRoundTrip() throws {
        let dir = TempDataDirectory()
        let store = LinkStore(fileURL: dir.file("links.json"))
        try store.add(link("a", "b", kind: .transfer, note: "Employer RRSP match"))
        try store.reject(HashPair("c", "d"), at: Date(timeIntervalSince1970: 1_700_000_100))

        let reloaded = LinkStore(fileURL: dir.file("links.json"))
        try reloaded.load()
        #expect(reloaded.links == store.links)
        #expect(reloaded.rejections == store.rejections)
        #expect(reloaded.links.first?.kind == .transfer)
        #expect(reloaded.links.first?.note == "Employer RRSP match")
    }

    @Test func addingLinkDropsMatchingRejection() throws {
        let dir = TempDataDirectory()
        let store = LinkStore(fileURL: dir.file("links.json"))
        try store.reject(HashPair("x", "y"))
        try store.add(link("y", "x"))
        #expect(store.rejections.isEmpty)
        #expect(store.links.count == 1)
    }

    @Test func rejectIsIdempotent() throws {
        let dir = TempDataDirectory()
        let store = LinkStore(fileURL: dir.file("links.json"))
        try store.reject(HashPair("x", "y"))
        try store.reject(HashPair("y", "x"))
        #expect(store.rejections.count == 1)
    }

    @Test func removeLinkByID() throws {
        let dir = TempDataDirectory()
        let store = LinkStore(fileURL: dir.file("links.json"))
        let ab = link("a", "b")
        try store.add(ab)
        try store.add(link("c", "d"))
        try store.removeLink(id: ab.id)
        #expect(store.links.map(\.pair) == [HashPair("c", "d")])
    }

    @Test func unlinkRemovesLinkAndRejectsPair() throws {
        let dir = TempDataDirectory()
        let store = LinkStore(fileURL: dir.file("links.json"))
        let ab = link("a", "b")
        try store.add(ab)
        try store.unlink(id: ab.id)
        let reloaded = LinkStore(fileURL: dir.file("links.json"))
        try reloaded.load()
        #expect(reloaded.links.isEmpty)
        #expect(reloaded.rejections.map(\.pair) == [HashPair("a", "b")])
    }

    @Test func removeAllMentioningCascades() throws {
        let dir = TempDataDirectory()
        let store = LinkStore(fileURL: dir.file("links.json"))
        try store.add(link("a", "b"))
        try store.add(link("c", "d"))
        try store.reject(HashPair("a", "e"))
        try store.removeAll(mentioning: "a")
        #expect(store.links.map(\.pair) == [HashPair("c", "d")])
        #expect(store.rejections.isEmpty)
    }

    /// A delete cascade with nothing to remove mustn't create or rewrite the file.
    @Test func removeAllWithNoMatchDoesNotWrite() throws {
        let dir = TempDataDirectory()
        let store = LinkStore(fileURL: dir.file("links.json"))
        try store.removeAll(mentioning: "a")
        #expect(!FileManager.default.fileExists(atPath: dir.file("links.json").path))
    }

    @Test func missingKeysDecodeAsEmpty() throws {
        let dir = TempDataDirectory()
        try Data("{}".utf8).write(to: dir.file("links.json"))
        let store = LinkStore(fileURL: dir.file("links.json"))
        try store.load()
        #expect(store.links.isEmpty)
        #expect(store.rejections.isEmpty)
    }
}
