import Foundation
import Testing
@testable import transactions_ui

@Suite("ReserveEventStore")
struct ReserveEventStoreTests {

    private func event(reserve: UUID = UUID(), account: UUID = UUID(),
                       type: ReserveEventType = .allocation, amount: Double = 100) -> ReserveEvent {
        ReserveEvent(date: Date(timeIntervalSince1970: 1_700_000_000),
                     reserveID: reserve, accountID: account, type: type, amount: amount)
    }

    @Test func appendPersistsAcrossInstances() throws {
        let dir = TempDataDirectory()
        let url = dir.file("reserveEvents.json")
        let store = ReserveEventStore(fileURL: url)
        try store.load()
        let e = event()
        try store.append(e)
        #expect(store.events.count == 1)

        let reloaded = ReserveEventStore(fileURL: url)
        try reloaded.load()
        #expect(reloaded.events == [e])
    }

    @Test func removeAllByReserveCascades() throws {
        let dir = TempDataDirectory()
        let store = ReserveEventStore(fileURL: dir.file("reserveEvents.json"))
        try store.load()
        let keep = UUID(); let drop = UUID()
        try store.append(event(reserve: drop))
        try store.append(event(reserve: drop))
        try store.append(event(reserve: keep))
        try store.removeAll(reserveID: drop)
        #expect(store.events.count == 1)
        #expect(store.events[0].reserveID == keep)
    }

    @Test func removeAllByAccountCascades() throws {
        let dir = TempDataDirectory()
        let store = ReserveEventStore(fileURL: dir.file("reserveEvents.json"))
        try store.load()
        let keep = UUID(); let drop = UUID()
        try store.append(event(account: drop))
        try store.append(event(account: keep))
        try store.removeAll(accountID: drop)
        #expect(store.events.count == 1)
        #expect(store.events[0].accountID == keep)
    }

    @Test func removeByEventIDRemovesOnlyThatEvent() throws {
        let dir = TempDataDirectory()
        let store = ReserveEventStore(fileURL: dir.file("reserveEvents.json"))
        try store.load()
        let keep = event(amount: 10)
        let drop = event(amount: 20)
        try store.append(keep)
        try store.append(drop)
        try store.remove(eventID: drop.id)
        #expect(store.events == [keep])
    }

    @Test func removeByEventIDPersistsAcrossInstances() throws {
        let dir = TempDataDirectory()
        let url = dir.file("reserveEvents.json")
        let store = ReserveEventStore(fileURL: url)
        try store.load()
        let keep = event(amount: 10)
        let drop = event(amount: 20)
        try store.append(keep)
        try store.append(drop)
        try store.remove(eventID: drop.id)

        let reloaded = ReserveEventStore(fileURL: url)
        try reloaded.load()
        #expect(reloaded.events == [keep])
    }

    @Test func loadMigratesFromLegacyReservations() throws {
        let dir = TempDataDirectory()
        // Seed a legacy reservations.json sibling; leave reserveEvents.json absent.
        let reserve = UUID(); let account = UUID()
        let legacy = [Reservation(id: UUID(), amount: 250,
                                  updatedAt: Date(timeIntervalSince1970: 1_600_000_000),
                                  reserveID: reserve, accountID: account),
                      Reservation(id: UUID(), amount: 0,           // zero rows are skipped
                                  updatedAt: Date(timeIntervalSince1970: 1_600_000_000),
                                  reserveID: UUID(), accountID: UUID())]
        try AtomicJSONFile.save(legacy, to: dir.file("reservations.json"))

        let store = ReserveEventStore(fileURL: dir.file("reserveEvents.json"))
        try store.load()

        #expect(store.events.count == 1)
        let seeded = store.events[0]
        #expect(seeded.type == .allocation)
        #expect(seeded.amount == 250)
        #expect(seeded.reserveID == reserve)
        #expect(seeded.accountID == account)
        #expect(seeded.date == Date(timeIntervalSince1970: 1_600_000_000))
        #expect(seeded.note == "Opening balance (migrated)")
        // reservations.json is left untouched.
        #expect(FileManager.default.fileExists(atPath: dir.file("reservations.json").path))
    }

    @Test func loadDoesNotMigrateWhenEventsFileExists() throws {
        let dir = TempDataDirectory()
        // Both files present: the events file wins, migration is skipped.
        try AtomicJSONFile.save([Reservation](), to: dir.file("reserveEvents.json"))
        try AtomicJSONFile.save(
            [Reservation(id: UUID(), amount: 999, updatedAt: Date(timeIntervalSince1970: 0),
                         reserveID: UUID(), accountID: UUID())],
            to: dir.file("reservations.json"))
        let store = ReserveEventStore(fileURL: dir.file("reserveEvents.json"))
        try store.load()
        #expect(store.events.isEmpty)
    }
}
