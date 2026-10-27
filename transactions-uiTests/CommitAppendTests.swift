import Foundation
import Testing
@testable import transactions_ui

@Suite("commitAppend")
struct CommitAppendTests {

    private static let header = "Date,Details,Debit,Credit"

    /// Build an AppViewModel wired to a temp dir. csvDirectory points at the
    /// same temp dir root so seeded CSVs are discovered by name.
    private func makeVM(dir: TempDataDirectory) -> AppViewModel {
        AppViewModel(
            accountStore: AccountStore(fileURL: dir.file("accounts.json")),
            reserveStore: ReserveStore(fileURL: dir.file("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.file("reserveEvents.json")),
            editStore: EditStore(fileURL: dir.file("edits.json")),
            csvDirectory: dir.url
        )
    }

    private func seedAccount(dir: TempDataDirectory, csvFileName: String) throws -> Account {
        let account = Account(
            id: UUID(),
            name: "Chequing",
            type: .chequing,
            initialBalance: 0,
            csvFileName: csvFileName
        )
        try AtomicJSONFile.save([account], to: dir.file("accounts.json"))
        return account
    }

    private func seedCsv(dir: TempDataDirectory, name: String, contents: String) throws {
        try contents.write(to: dir.file(name), atomically: true, encoding: .utf8)
    }

    @Test("Appends new rows, preserves existing rows byte-for-byte")
    func happyPath() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }

        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        let existingCsv = """
        \(Self.header)
        2026-05-01,COFFEE SHOP,4.50,
        2026-05-02,PAYCHECK,,2000.00
        """
        try seedCsv(dir: dir, name: "chq.csv", contents: existingCsv)

        let vm = makeVM(dir: dir)
        #expect(vm.allTransactions.filter { $0.accountID == account.id }.count == 2)

        let addedRawLines = [
            "2026-06-01,LATE COFFEE,3.75,",
            "2026-06-02,BONUS,,500.00",
        ]

        let ok = vm.commitAppend(addedRawLines: addedRawLines, into: account)
        #expect(ok == true)
        #expect(vm.lastSaveError == nil)

        let after = vm.allTransactions.filter { $0.accountID == account.id }
        #expect(after.count == 4)
        #expect(after.contains { $0.details == "COFFEE SHOP" })
        #expect(after.contains { $0.details == "PAYCHECK" })
        #expect(after.contains { $0.details == "LATE COFFEE" })
        #expect(after.contains { $0.details == "BONUS" })

        let onDisk = try String(contentsOf: dir.file("chq.csv"), encoding: .utf8)
        #expect(onDisk.hasSuffix("\n"))
        #expect(onDisk.contains("2026-05-01,COFFEE SHOP,4.50,"))
        #expect(onDisk.contains("2026-05-02,PAYCHECK,,2000.00"))
        #expect(onDisk.contains("2026-06-01,LATE COFFEE,3.75,"))
        #expect(onDisk.contains("2026-06-02,BONUS,,500.00"))
    }

    @Test("Empty addedRawLines normalizes trailing whitespace to exactly one \\n")
    func emptyAddedNormalizesTrailingNewline() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }

        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        // Deliberately no trailing newline in seed — commitAppend normalizes to one.
        let existingCsv = "\(Self.header)\n2026-05-01,COFFEE SHOP,4.50,"
        try seedCsv(dir: dir, name: "chq.csv", contents: existingCsv)

        let vm = makeVM(dir: dir)
        let before = vm.allTransactions.filter { $0.accountID == account.id }.count

        let ok = vm.commitAppend(addedRawLines: [], into: account)
        #expect(ok == true)
        #expect(vm.lastSaveError == nil)

        let after = vm.allTransactions.filter { $0.accountID == account.id }.count
        #expect(after == before)

        let onDisk = try String(contentsOf: dir.file("chq.csv"), encoding: .utf8)
        // Normalized form: no trailing whitespace + exactly one \n
        #expect(onDisk == existingCsv + "\n")
    }

    @Test("Edits on pre-existing rows survive an append across reload")
    func editsSurviveAppendAcrossReload() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }

        let account = try seedAccount(dir: dir, csvFileName: "chq.csv")
        let existingCsv = """
        \(Self.header)
        2026-05-01,COFFEE SHOP,4.50,
        """
        try seedCsv(dir: dir, name: "chq.csv", contents: existingCsv)

        let vm1 = makeVM(dir: dir)
        guard let existing = vm1.allTransactions.first(where: { $0.details == "COFFEE SHOP" }) else {
            Issue.record("seed row missing")
            return
        }
        let hashBefore = existing.contentHash
        #expect(vm1.saveEdit(
            for: existing,
            category: CategoryID(rawValue: "food"),
            subcategory: nil,
            notes: "morning-standup"
        ) == true)

        let addedRawLines = ["2026-06-01,LATE COFFEE,3.75,"]
        #expect(vm1.commitAppend(addedRawLines: addedRawLines, into: account) == true)

        // Fresh VM against the same temp dir — reload from disk.
        let vm2 = makeVM(dir: dir)
        let reloaded = vm2.allTransactions.first { $0.details == "COFFEE SHOP" }
        #expect(reloaded != nil)
        #expect(reloaded?.contentHash == hashBefore)
        #expect(reloaded?.edit?.notes == "morning-standup")
        #expect(vm2.allTransactions.filter { $0.accountID == account.id }.count == 2)
    }

    @Test("Creates the CSV when it doesn't exist yet (first upload)")
    func createsMissingFile() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }

        let account = try seedAccount(dir: dir, csvFileName: "new.csv")
        // No CSV on disk — this is the create-mode first-upload path.
        #expect(FileManager.default.fileExists(atPath: dir.file("new.csv").path) == false)

        let vm = makeVM(dir: dir)
        #expect(vm.allTransactions.filter { $0.accountID == account.id }.isEmpty)

        let addedRawLines = [
            "2026-06-01,LATE COFFEE,3.75,",
            "2026-06-02,BONUS,,500.00",
        ]
        let ok = vm.commitAppend(addedRawLines: addedRawLines, into: account)
        #expect(ok == true)
        #expect(vm.lastSaveError == nil)

        let after = vm.allTransactions.filter { $0.accountID == account.id }
        // Both rows imported: parser now skips the position-zero line only
        // when it isn't a valid date, so headerless CSVs (CIBC) keep their
        // first data row.
        #expect(after.count == 2)
        #expect(after.contains { $0.details == "LATE COFFEE" })
        #expect(after.contains { $0.details == "BONUS" })

        let onDisk = try String(contentsOf: dir.file("new.csv"), encoding: .utf8)
        #expect(onDisk.hasSuffix("\n"))
        #expect(onDisk.hasPrefix("2026-06-01,LATE COFFEE,3.75,"))
    }
}
