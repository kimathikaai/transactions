import Foundation
import Testing
@testable import transactions_ui

@Suite("ReserveService")
struct ReserveServiceTests {

    private func setup() -> (ReserveService, ReserveEventStore, TempDataDirectory) {
        let dir = TempDataDirectory()
        let store = ReserveEventStore(fileURL: dir.file("reserveEvents.json"))
        try? store.load()
        return (ReserveService(eventStore: store), store, dir)
    }

    private let acct = Account(id: UUID(), name: "A", type: .chequing,
                               initialBalance: 100, csvFileName: "a.csv")
    private let rsv = Reserve(id: UUID(), name: "B", emoji: "💰", colorHex: "#000",
                             target: 0, tagline: "", createdAt: Date(timeIntervalSince1970: 0),
                             sortOrder: 0)

    // MARK: - claim

    @Test func claimRejectsZero() throws {
        let (svc, _, _) = setup()
        #expect(throws: ReserveError.invalidAmount) {
            try svc.claim(amount: 0, from: acct, freeAvailable: 100, to: rsv, note: nil)
        }
    }

    @Test func claimRejectsAboveFree() throws {
        let (svc, _, _) = setup()
        #expect(throws: (any Error).self) {
            try svc.claim(amount: 200, from: acct, freeAvailable: 100, to: rsv, note: nil)
        }
    }

    @Test func claimThrowsInsufficientFreeWithCorrectPayload() throws {
        let (svc, _, _) = setup()
        do {
            try svc.claim(amount: 200, from: acct, freeAvailable: 100, to: rsv, note: nil)
            Issue.record("Expected throw")
        } catch let ReserveError.insufficientFree(accountID, requested, available) {
            #expect(accountID == acct.id)
            #expect(requested == 200)
            #expect(available == 100)
        }
    }

    @Test func claimAppendsAllocationEvent() throws {
        let (svc, store, _) = setup()
        try svc.claim(amount: 25, from: acct, freeAvailable: 100, to: rsv, note: "rainy day")
        #expect(store.events.count == 1)
        #expect(store.events[0].type == .allocation)
        #expect(store.events[0].amount == 25)
        #expect(store.events[0].reserveID == rsv.id)
        #expect(store.events[0].accountID == acct.id)
        #expect(store.events[0].note == "rainy day")
    }

    @Test func claimTwiceAppendsTwoEventsFoldingToSum() throws {
        let (svc, store, _) = setup()
        try svc.claim(amount: 25, from: acct, freeAvailable: 100, to: rsv, note: nil)
        try svc.claim(amount: 15, from: acct, freeAvailable: 75, to: rsv, note: nil)
        #expect(store.events.count == 2)
        let folded = foldEvents(store.events)
        #expect(folded.count == 1)
        #expect(folded[0].amount == 40)
    }

    // MARK: - release

    @Test func releaseAppendsReleaseEventFoldingToZero() throws {
        let (svc, store, _) = setup()
        try svc.claim(amount: 25, from: acct, freeAvailable: 100, to: rsv, note: nil)
        try svc.release(amount: 25, from: rsv, to: acct, availableForAccountInReserve: 25, note: nil)
        #expect(store.events.count == 2)
        #expect(foldEvents(store.events).isEmpty)
    }

    @Test func releaseSubtractsWhenPartial() throws {
        let (svc, store, _) = setup()
        try svc.claim(amount: 50, from: acct, freeAvailable: 100, to: rsv, note: nil)
        try svc.release(amount: 20, from: rsv, to: acct, availableForAccountInReserve: 50, note: nil)
        let folded = foldEvents(store.events)
        #expect(folded.count == 1)
        #expect(folded[0].amount == 30)
    }

    @Test func releaseRejectsZero() throws {
        let (svc, _, _) = setup()
        try svc.claim(amount: 25, from: acct, freeAvailable: 100, to: rsv, note: nil)
        #expect(throws: ReserveError.invalidAmount) {
            try svc.release(amount: 0, from: rsv, to: acct, availableForAccountInReserve: 25, note: nil)
        }
    }

    @Test func releaseRejectsAboveAvailable() throws {
        let (svc, _, _) = setup()
        try svc.claim(amount: 25, from: acct, freeAvailable: 100, to: rsv, note: nil)
        #expect(throws: (any Error).self) {
            try svc.release(amount: 999, from: rsv, to: acct, availableForAccountInReserve: 25, note: nil)
        }
    }

    @Test func releaseThrowsInsufficientReservationWithCorrectPayload() throws {
        let (svc, _, _) = setup()
        try svc.claim(amount: 25, from: acct, freeAvailable: 100, to: rsv, note: nil)
        do {
            try svc.release(amount: 999, from: rsv, to: acct, availableForAccountInReserve: 25, note: nil)
            Issue.record("Expected throw")
        } catch let ReserveError.insufficientReservation(reserveID, accountID, requested, available) {
            #expect(reserveID == rsv.id)
            #expect(accountID == acct.id)
            #expect(requested == 999)
            #expect(available == 25)
        }
    }

    // MARK: - use

    @Test func useRejectsZero() throws {
        let (svc, _, _) = setup()
        #expect(throws: ReserveError.invalidAmount) {
            try svc.use(amount: 0, from: acct, on: rsv, availableForAccountInReserve: 50,
                             transactionContentHash: "tx1", alreadyLinked: false, note: nil)
        }
    }

    @Test func useRejectsAlreadyLinked() throws {
        let (svc, _, _) = setup()
        #expect(throws: ReserveError.transactionAlreadyLinked(contentHash: "tx1")) {
            try svc.use(amount: 20, from: acct, on: rsv, availableForAccountInReserve: 50,
                             transactionContentHash: "tx1", alreadyLinked: true, note: nil)
        }
    }

    @Test func useRejectsAboveAvailableWithCorrectPayload() throws {
        let (svc, _, _) = setup()
        do {
            try svc.use(amount: 80, from: acct, on: rsv, availableForAccountInReserve: 50,
                             transactionContentHash: "tx1", alreadyLinked: false, note: nil)
            Issue.record("Expected throw")
        } catch let ReserveError.insufficientReservation(reserveID, accountID, requested, available) {
            #expect(reserveID == rsv.id)
            #expect(accountID == acct.id)
            #expect(requested == 80)
            #expect(available == 50)
        }
    }

    @Test func useAppendsUseEventWithContentHash() throws {
        let (svc, store, _) = setup()
        try svc.claim(amount: 50, from: acct, freeAvailable: 100, to: rsv, note: nil)
        try svc.use(amount: 20, from: acct, on: rsv, availableForAccountInReserve: 50,
                         transactionContentHash: "flight-hash", alreadyLinked: false, note: "flight")
        #expect(store.events.count == 2)
        let ex = store.events[1]
        #expect(ex.type == .use)
        #expect(ex.amount == 20)
        #expect(ex.reserveID == rsv.id)
        #expect(ex.accountID == acct.id)
        #expect(ex.transactionContentHash == "flight-hash")
        #expect(ex.note == "flight")
    }

    @Test func useFoldsDownHeldLikeRelease() throws {
        let (svc, store, _) = setup()
        try svc.claim(amount: 50, from: acct, freeAvailable: 100, to: rsv, note: nil)
        try svc.use(amount: 20, from: acct, on: rsv, availableForAccountInReserve: 50,
                         transactionContentHash: "tx1", alreadyLinked: false, note: nil)
        let folded = foldEvents(store.events)
        #expect(folded.count == 1)
        #expect(folded[0].amount == 30)   // held = 50 − 20
    }

    // MARK: - deleteReserve (cascade)

    @Test func deleteReserveCascadesEvents() throws {
        let dir = TempDataDirectory()
        let eventStore = ReserveEventStore(fileURL: dir.file("reserveEvents.json"))
        try eventStore.load()
        let reserveStore = ReserveStore(fileURL: dir.file("reserves.json"))

        let acct2 = Account(id: UUID(), name: "B", type: .savings,
                            initialBalance: 500, csvFileName: "b.csv")
        try reserveStore.upsert(rsv)

        let svc = ReserveService(eventStore: eventStore)
        try svc.claim(amount: 25, from: acct, freeAvailable: 100, to: rsv, note: nil)
        try svc.claim(amount: 50, from: acct2, freeAvailable: 500, to: rsv, note: nil)
        #expect(eventStore.events.count == 2)

        try svc.deleteReserve(id: rsv.id, from: reserveStore)
        #expect(reserveStore.reserves.isEmpty)
        #expect(eventStore.events.isEmpty)
    }
}
