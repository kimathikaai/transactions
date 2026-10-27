import Testing
import Foundation
@testable import transactions_ui

struct BankCsvParserTests {

    @Test("Parses bank CSV with quoted-comma details")
    func quotedComma() throws {
        let csv = """
        Date,Details,Debit,Credit,
        2026-04-07,"GAME STORE 800-555-0100, CA",9.03,,4500********0000
        """
        let rows = try BankCsvParser.parse(csvString: csv)
        #expect(rows.count == 1)
        #expect(rows[0].row.details == "GAME STORE 800-555-0100, CA")
        #expect(rows[0].row.debit == 9.03)
        #expect(rows[0].row.credit == 0.0)
    }

    @Test("Trailing 5th column (card mask) is ignored")
    func trailingColumnIgnored() throws {
        let csv = """
        Date,Details,Debit,Credit,
        2026-04-08,PAYMENT THANK YOU/PAIEMEN T MERCI,,1250.5,4500********0001
        """
        let rows = try BankCsvParser.parse(csvString: csv)
        #expect(rows.count == 1)
        #expect(rows[0].row.credit == 1250.5)
        #expect(rows[0].row.debit == 0.0)
    }

    @Test("Empty details throws emptyDetails")
    func emptyDetailsThrows() {
        let csv = """
        Date,Details,Debit,Credit
        2026-01-01,,5.00,
        """
        #expect(throws: BankCsvParserError.self) {
            try BankCsvParser.parse(csvString: csv)
        }
    }

    @Test("Both-zero amount throws zeroAmount")
    func zeroAmountThrows() {
        let csv = """
        Date,Details,Debit,Credit
        2026-01-01,SOMETHING,,
        """
        #expect(throws: BankCsvParserError.self) {
            try BankCsvParser.parse(csvString: csv)
        }
    }

    @Test("Invalid date throws invalidDate")
    func invalidDateThrows() {
        let csv = """
        Date,Details,Debit,Credit
        2026/01/01,SOMETHING,5.00,
        """
        #expect(throws: BankCsvParserError.self) {
            try BankCsvParser.parse(csvString: csv)
        }
    }

    @Test("Empty CSV body returns empty rows")
    func emptyBody() throws {
        let csv = "Date,Details,Debit,Credit\n"
        let rows = try BankCsvParser.parse(csvString: csv)
        #expect(rows.isEmpty)
    }

    @Test("Error message mentions the line number")
    func errorMessageIncludesLine() {
        do {
            _ = try BankCsvParser.parse(csvString: "Date,Details,Debit,Credit\n2026/01/01,X,5,\n")
            Issue.record("expected throw")
        } catch let error as BankCsvParserError {
            #expect(error.description.contains("line 2"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("Each parsed row carries its raw source line (CR stripped)")
    func rawLineRoundtrip() throws {
        let csv = "Date,Details,Debit,Credit\r\n2026-04-07,\"GAME STORE 800-555-0100, CA\",9.03,\r\n2026-04-08,PAYMENT THANK YOU/PAIEMEN T MERCI,,1250.5\r\n"
        let parsed = try BankCsvParser.parse(csvString: csv)
        #expect(parsed.count == 2)
        #expect(parsed[0].rawLine == "2026-04-07,\"GAME STORE 800-555-0100, CA\",9.03,")
        #expect(parsed[1].rawLine == "2026-04-08,PAYMENT THANK YOU/PAIEMEN T MERCI,,1250.5")
        #expect(parsed[0].row.details == "GAME STORE 800-555-0100, CA")
        #expect(parsed[1].row.credit == 1250.5)
    }

    @Test("Headerless CSV keeps its first data row (CIBC-style export)")
    func headerlessKeepsFirstRow() throws {
        // CIBC exports have no header line — the position-zero row is real data.
        // Verifies the shape-based header detection replaces the old
        // `index == 0` unconditional skip.
        let csv = """
        2026-06-29,Internet Banking E-TRANSFER 100000000001 Jane Doe,120.00,
        2026-06-29,Internet Banking INTERNET TRANSFER 000000000002 TO ACCOUNT 00000/****000,2500.00,
        """
        let parsed = try BankCsvParser.parse(csvString: csv)
        #expect(parsed.count == 2)
        #expect(parsed[0].row.debit == 120.00)
        #expect(parsed[0].row.details.hasPrefix("Internet Banking E-TRANSFER"))
        #expect(parsed[1].row.debit == 2500.00)
    }
}
