import Foundation
import Testing
@testable import transactions_ui

@Suite("AtomicJSONFile")
struct AtomicJSONFileTests {

    struct Payload: Codable, Equatable {
        let name: String
        let count: Int
    }

    @Test func roundTripEncodesAndDecodes() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = Payload(name: "hello", count: 42)
        try AtomicJSONFile.save(original, to: tmp)
        let decoded: Payload? = try AtomicJSONFile.load(Payload.self, from: tmp)
        #expect(decoded == original)
    }

    @Test func loadReturnsNilForMissingFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        let decoded: Payload? = try AtomicJSONFile.load(Payload.self, from: tmp)
        #expect(decoded == nil)
    }

    @Test func encoderOutputIsPrettyAndSortedKeys() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try AtomicJSONFile.save(Payload(name: "z", count: 1), to: tmp)
        let raw = try String(contentsOf: tmp, encoding: .utf8)
        // Sorted keys → "count" comes before "name" alphabetically.
        let countIdx = raw.range(of: "\"count\"")!.lowerBound
        let nameIdx = raw.range(of: "\"name\"")!.lowerBound
        #expect(countIdx < nameIdx)
        #expect(raw.contains("\n"))  // pretty-printed
    }
}
