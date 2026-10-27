import Foundation
import Testing
@testable import transactions_ui

@Suite("ReserveEventFold")
struct ReserveEventFoldTests {

    @Test func reserveEventRoundTripsThroughCodec() throws {
        let event = ReserveEvent(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            reserveID: UUID(), accountID: UUID(),
            type: .release, amount: 42.5, note: "partial withdraw"
        )
        let data = try AtomicJSONFile.encoder().encode(event)
        let decoded = try AtomicJSONFile.decoder().decode(ReserveEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test func reserveEventEncodesNilNoteAsAbsent() throws {
        let event = ReserveEvent(reserveID: UUID(), accountID: UUID(),
                                 type: .allocation, amount: 10, note: nil)
        let data = try AtomicJSONFile.encoder().encode(event)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("note"))
    }

    @Test func foldSumsAllocationsMinusReleasesPerPair() {
        let reserve = UUID(); let account = UUID()
        let events = [
            ReserveEvent(date: Date(timeIntervalSince1970: 10),
                         reserveID: reserve, accountID: account, type: .allocation, amount: 50),
            ReserveEvent(date: Date(timeIntervalSince1970: 20),
                         reserveID: reserve, accountID: account, type: .release, amount: 20),
        ]
        let reservations = foldEvents(events)
        #expect(reservations.count == 1)
        #expect(reservations[0].reserveID == reserve)
        #expect(reservations[0].accountID == account)
        #expect(reservations[0].amount == 30)
        // updatedAt tracks the latest event.
        #expect(reservations[0].updatedAt == Date(timeIntervalSince1970: 20))
    }

    @Test func foldDropsNearZeroPairs() {
        let reserve = UUID(); let account = UUID()
        let events = [
            ReserveEvent(reserveID: reserve, accountID: account, type: .allocation, amount: 25),
            ReserveEvent(reserveID: reserve, accountID: account, type: .release, amount: 25),
        ]
        #expect(foldEvents(events).isEmpty)
    }

    @Test func foldSeparatesDistinctPairs() {
        let reserve = UUID()
        let acctA = UUID(); let acctB = UUID()
        let events = [
            ReserveEvent(reserveID: reserve, accountID: acctA, type: .allocation, amount: 10),
            ReserveEvent(reserveID: reserve, accountID: acctB, type: .allocation, amount: 40),
        ]
        let reservations = foldEvents(events)
        #expect(reservations.count == 2)
        #expect(reservations.first { $0.accountID == acctA }?.amount == 10)
        #expect(reservations.first { $0.accountID == acctB }?.amount == 40)
    }

    @Test func foldOfEmptyLogIsEmpty() {
        #expect(foldEvents([]).isEmpty)
    }

    // MARK: - use

    @Test func legacyExerciseRawValueDecodesAsUse() throws {
        // Ledgers written before the "exercise" → "use" rename persisted the
        // event type as the raw string "exercise". The tolerant decoder maps it.
        let json = """
        {"id":"\(UUID().uuidString)","date":"2024-01-01T00:00:00Z","reserveID":"\(UUID().uuidString)",\
        "accountID":"\(UUID().uuidString)","type":"exercise","amount":25}
        """
        let decoded = try AtomicJSONFile.decoder().decode(ReserveEvent.self, from: Data(json.utf8))
        #expect(decoded.type == .use)
    }

    @Test func useEncodesRawValueAsUse() throws {
        let event = ReserveEvent(reserveID: UUID(), accountID: UUID(), type: .use, amount: 10)
        let data = try AtomicJSONFile.encoder().encode(event)
        let str = String(decoding: data, as: UTF8.self)
        #expect(str.contains("\"use\""))
        #expect(!str.contains("exercise"))
    }

    @Test func reserveEventRoundTripsWithTransactionHash() throws {
        let event = ReserveEvent(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            reserveID: UUID(), accountID: UUID(),
            type: .use, amount: 60, note: "flight",
            transactionContentHash: "abc123def456"
        )
        let data = try AtomicJSONFile.encoder().encode(event)
        let decoded = try AtomicJSONFile.decoder().decode(ReserveEvent.self, from: data)
        #expect(decoded == event)
        #expect(decoded.transactionContentHash == "abc123def456")
    }

    @Test func reserveEventEncodesNilTransactionHashAsAbsent() throws {
        let event = ReserveEvent(reserveID: UUID(), accountID: UUID(),
                                 type: .allocation, amount: 10)
        let data = try AtomicJSONFile.encoder().encode(event)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("transactionContentHash"))
    }

    @Test func foldSubtractsUsesLikeReleases() {
        let reserve = UUID(); let account = UUID()
        let events = [
            ReserveEvent(date: Date(timeIntervalSince1970: 10),
                         reserveID: reserve, accountID: account, type: .allocation, amount: 50),
            ReserveEvent(date: Date(timeIntervalSince1970: 20),
                         reserveID: reserve, accountID: account, type: .use, amount: 20,
                         transactionContentHash: "tx1"),
        ]
        let reservations = foldEvents(events)
        #expect(reservations.count == 1)
        #expect(reservations[0].amount == 30)   // held = 50 − 20
    }

    @Test func usedSumsOnlyUseEvents() {
        let reserve = UUID(); let account = UUID()
        let events = [
            ReserveEvent(reserveID: reserve, accountID: account, type: .allocation, amount: 100),
            ReserveEvent(reserveID: reserve, accountID: account, type: .release, amount: 10),
            ReserveEvent(reserveID: reserve, accountID: account, type: .use, amount: 20,
                         transactionContentHash: "tx1"),
            ReserveEvent(reserveID: reserve, accountID: account, type: .use, amount: 5,
                         transactionContentHash: "tx2"),
        ]
        #expect(used(of: reserve, events: events) == 25)
    }

    @Test func usedTransactionIDsCollectsLinkedHashes() {
        let reserve = UUID(); let account = UUID()
        let events = [
            ReserveEvent(reserveID: reserve, accountID: account, type: .allocation, amount: 100),
            ReserveEvent(reserveID: reserve, accountID: account, type: .use, amount: 20,
                         transactionContentHash: "tx1"),
            ReserveEvent(reserveID: reserve, accountID: account, type: .use, amount: 5,
                         transactionContentHash: "tx2"),
        ]
        #expect(usedTransactionIDs(events: events) == ["tx1", "tx2"])
    }

    @Test func filledIsInvariantToExercising() {
        let reserve = Reserve(id: UUID(), name: "Vacation", emoji: "🏖️", colorHex: "#000",
                              target: 2_000, tagline: "",
                              createdAt: Date(timeIntervalSince1970: 0), sortOrder: 0)
        let account = UUID()
        // Allocate 1000; held = 1000, used = 0, filled = 1000.
        var events = [
            ReserveEvent(reserveID: reserve.id, accountID: account, type: .allocation, amount: 1_000),
        ]
        let before = filled(of: reserve, reservations: foldEvents(events), events: events)
        #expect(before == 1_000)

        // Use 600; held = 400, used = 600, filled still 1000.
        events.append(ReserveEvent(reserveID: reserve.id, accountID: account, type: .use,
                                   amount: 600, transactionContentHash: "tx1"))
        let after = filled(of: reserve, reservations: foldEvents(events), events: events)
        #expect(after == 1_000)
        #expect(total(of: reserve.id, reservations: foldEvents(events)) == 400)   // held dropped
        #expect(used(of: reserve.id, events: events) == 600)
        #expect(filledProgress(of: reserve, reservations: foldEvents(events), events: events) == 0.5)
    }

    @Test func isAtFilledTargetCountsHeldPlusUsed() {
        let reserve = Reserve(id: UUID(), name: "Bike", emoji: "🚲", colorHex: "#000",
                              target: 800, tagline: "",
                              createdAt: Date(timeIntervalSince1970: 0), sortOrder: 0)
        let account = UUID()
        // Allocate 800, use 800: held 0, used 800, filled 800 → at target.
        let events = [
            ReserveEvent(reserveID: reserve.id, accountID: account, type: .allocation, amount: 800),
            ReserveEvent(reserveID: reserve.id, accountID: account, type: .use, amount: 800,
                         transactionContentHash: "tx1"),
        ]
        let folded = foldEvents(events)
        #expect(total(of: reserve.id, reservations: folded) == 0)        // nothing held
        #expect(isAtFilledTarget(reserve, reservations: folded, events: events))
        #expect(!isAtTarget(reserve, reservations: folded))              // held-only view is not at target
    }
}
