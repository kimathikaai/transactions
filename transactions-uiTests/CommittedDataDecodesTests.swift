import Foundation
import Testing
@testable import transactions_ui

/// Guards that the committed demo JSON files decode cleanly into the
/// record structs. If someone renames a field on disk without updating the
/// struct (or vice versa), this fails immediately rather than at app launch.
@Suite("Committed Data Decodes")
struct CommittedDataDecodesTests {

    @Test func accountsFileDecodes() throws {
        let records: [Account]? = try AtomicJSONFile.load(
            [Account].self, from: DataPaths.accountsFile(for: .demo)
        )
        #expect(records != nil)
        #expect((records ?? []).isEmpty == false)
    }

    @Test func reservesFileDecodes() throws {
        _ = try AtomicJSONFile.load([Reserve].self, from: DataPaths.reservesFile(for: .demo))
    }

    @Test func reservationsFileDecodes() throws {
        _ = try AtomicJSONFile.load([Reservation].self, from: DataPaths.reservationsFile(for: .demo))
    }

    @Test func editsFileDecodes() throws {
        _ = try AtomicJSONFile.load([String: TransactionEdit].self, from: DataPaths.editsFile(for: .demo))
    }
}
