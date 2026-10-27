import Foundation
import Testing
@testable import transactions_ui

@Suite("AccountRecord")
struct AccountRecordTests {

    @Test func roundTripsThroughJSON() throws {
        let record = Account(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Chequing",
            type: .chequing,
            initialBalance: 123.45,
            csvFileName: "chequing.csv"
        )
        let data = try AtomicJSONFile.encoder().encode([record])
        let decoded = try AtomicJSONFile.decoder().decode([Account].self, from: data)
        #expect(decoded == [record])
    }

    @Test func acceptsLegacyExportedShape() throws {
        // Matches what JSONExporter emitted in PR 1.
        let json = """
        [
          {
            "csvFileName": "chequing.csv",
            "id": "11111111-1111-1111-1111-111111111111",
            "initialBalance": 100,
            "name": "Chequing",
            "type": "chequing"
          }
        ]
        """
        let data = Data(json.utf8)
        let decoded = try AtomicJSONFile.decoder().decode([Account].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].name == "Chequing")
        #expect(decoded[0].csvFileName == "chequing.csv")
    }
}
