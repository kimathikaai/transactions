import Foundation
import Testing
@testable import transactions_ui

@Suite("ReimbursementLink")
struct ReimbursementLinkTests {

    @Test func roundTripsWithNote() throws {
        let record = ReimbursementLink(
            reimbursementHash: "income-hash-1",
            amount: 42.50,
            linkedAt: Date(timeIntervalSince1970: 1_700_000_000),
            note: "work trip · flight"
        )
        let data = try AtomicJSONFile.encoder().encode([record])
        let decoded = try AtomicJSONFile.decoder().decode([ReimbursementLink].self, from: data)
        #expect(decoded == [record])
    }

    @Test func roundTripsWithoutNote() throws {
        let record = ReimbursementLink(
            reimbursementHash: "income-hash-2",
            amount: 100,
            linkedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(record.note == nil)
        let data = try AtomicJSONFile.encoder().encode([record])
        let decoded = try AtomicJSONFile.decoder().decode([ReimbursementLink].self, from: data)
        #expect(decoded == [record])
    }

    /// The store persists links keyed by the reimbursed expense's contentHash
    /// (mirroring `edits.json`), so verify the `[String: ReimbursementLink]`
    /// shape round-trips.
    @Test func keyedByExpenseHashRoundTrips() throws {
        let links: [String: ReimbursementLink] = [
            "expense-hash-a": ReimbursementLink(
                reimbursementHash: "income-hash-1",
                amount: 30,
                linkedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]
        let data = try AtomicJSONFile.encoder().encode(links)
        let decoded = try AtomicJSONFile.decoder().decode([String: ReimbursementLink].self, from: data)
        #expect(decoded == links)
    }

    /// A nil note must be omitted from the JSON (not encoded as `null`),
    /// matching the reserve-event convention.
    @Test func nilNoteIsOmittedFromJSON() throws {
        let record = ReimbursementLink(reimbursementHash: "income-hash-3", amount: 5)
        let data = try AtomicJSONFile.encoder().encode(record)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("note"))
    }
}
