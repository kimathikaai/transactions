import Foundation
import Testing
@testable import transactions_ui

@Suite("Record Codable")
struct RecordCodableTests {

    @Test func reserveRoundTrips() throws {
        let record = Reserve(
            id: UUID(),
            name: "Emergency",
            emoji: "🚨",
            colorHex: "#FF0000",
            target: 5000,
            tagline: "peace of mind",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            sortOrder: 3
        )
        let data = try AtomicJSONFile.encoder().encode([record])
        let decoded = try AtomicJSONFile.decoder().decode([Reserve].self, from: data)
        #expect(decoded == [record])
    }

    @Test func reservationRoundTrips() throws {
        let record = Reservation(
            id: UUID(),
            amount: 250,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            reserveID: UUID(),
            accountID: UUID()
        )
        let data = try AtomicJSONFile.encoder().encode([record])
        let decoded = try AtomicJSONFile.decoder().decode([Reservation].self, from: data)
        #expect(decoded == [record])
    }

    @Test func editsMapRoundTrips() throws {
        let edits: [String: TransactionEdit] = [
            "abc123": TransactionEdit(
                category: CategoryID(rawValue: "transport"),
                subcategory: SubcategoryID(rawValue: "transport.gas"),
                notes: "fill up",
                transactionType: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]
        let data = try AtomicJSONFile.encoder().encode(edits)
        let decoded = try AtomicJSONFile.decoder().decode([String: TransactionEdit].self, from: data)
        #expect(decoded == edits)
    }
}
