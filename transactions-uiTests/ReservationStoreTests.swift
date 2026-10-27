import Foundation
import Testing
@testable import transactions_ui

@Suite("ReservationStore")
struct ReservationStoreTests {

    private func sample(reserve: UUID = UUID(), account: UUID = UUID()) -> Reservation {
        Reservation(
            id: UUID(), amount: 100,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            reserveID: reserve, accountID: account
        )
    }

    @Test func upsertAndDelete() throws {
        let dir = TempDataDirectory()
        let store = ReservationStore(fileURL: dir.file("reservations.json"))
        let a = sample()
        try store.upsert(a)
        #expect(store.reservations.count == 1)
        try store.delete(id: a.id)
        #expect(store.reservations.isEmpty)
    }

    @Test func removeAllByAccountCascades() throws {
        let dir = TempDataDirectory()
        let store = ReservationStore(fileURL: dir.file("reservations.json"))
        let accountA = UUID(); let accountB = UUID()
        try store.upsert(sample(account: accountA))
        try store.upsert(sample(account: accountA))
        try store.upsert(sample(account: accountB))
        try store.removeAll(accountID: accountA)
        #expect(store.reservations.count == 1)
        #expect(store.reservations[0].accountID == accountB)
    }

    @Test func removeAllByReserveCascades() throws {
        let dir = TempDataDirectory()
        let store = ReservationStore(fileURL: dir.file("reservations.json"))
        let reserveA = UUID(); let reserveB = UUID()
        try store.upsert(sample(reserve: reserveA))
        try store.upsert(sample(reserve: reserveB))
        try store.removeAll(reserveID: reserveA)
        #expect(store.reservations.count == 1)
        #expect(store.reservations[0].reserveID == reserveB)
    }

    @Test func validateSeparatesLiveFromDangling() {
        let liveAccount = UUID(); let liveReserve = UUID()
        let deadAccount = UUID(); let deadReserve = UUID()
        let good = Reservation(id: UUID(), amount: 1,
                                    updatedAt: Date(timeIntervalSince1970: 0),
                                    reserveID: liveReserve, accountID: liveAccount)
        let badAccount = Reservation(id: UUID(), amount: 1,
                                          updatedAt: Date(timeIntervalSince1970: 0),
                                          reserveID: liveReserve, accountID: deadAccount)
        let badReserve = Reservation(id: UUID(), amount: 1,
                                         updatedAt: Date(timeIntervalSince1970: 0),
                                         reserveID: deadReserve, accountID: liveAccount)
        let (kept, dropped) = ReservationStore.validate(
            reservations: [good, badAccount, badReserve],
            againstAccounts: [liveAccount],
            reserves: [liveReserve]
        )
        #expect(kept == [good])
        #expect(Set(dropped.map(\.id)) == Set([badAccount.id, badReserve.id]))
    }
}
