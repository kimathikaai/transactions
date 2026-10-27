import Foundation

struct BankRow {
    let date: Date
    let details: String
    let debit: Double
    let credit: Double
}

/// A parsed row bundled with the exact source line it came from, with any
/// trailing "\r" stripped. Consumers that need to write the same row back to
/// disk (e.g. the CSV append path) can pass the raw line through byte-for-byte.
struct ParsedRow {
    let row: BankRow
    let rawLine: String
}

enum BankCsvParserError: Error, CustomStringConvertible {
    case malformedRow(line: Int, columnCount: Int)
    case invalidDate(line: Int, raw: String)
    case invalidNumber(line: Int, field: String, raw: String)
    case emptyDetails(line: Int)
    case zeroAmount(line: Int)

    var description: String {
        switch self {
        case .malformedRow(let line, let columnCount):
            return "line \(line): expected at least 4 columns, got \(columnCount)"
        case .invalidDate(let line, let raw):
            return "line \(line): invalid date \(raw.debugDescription) (expected yyyy-MM-dd)"
        case .invalidNumber(let line, let field, let raw):
            return "line \(line): invalid \(field) value \(raw.debugDescription)"
        case .emptyDetails(let line):
            return "line \(line): empty details"
        case .zeroAmount(let line):
            return "line \(line): both debit and credit are zero"
        }
    }
}

enum BankCsvParser {

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.isLenient = false
        return fmt
    }()

    static func parse(csvString: String) throws -> [ParsedRow] {
        let lines = csvString.components(separatedBy: .newlines)
        var parsed: [ParsedRow] = []
        parsed.reserveCapacity(lines.count)

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.isEmpty { continue }
            let lineNumber = index + 1
            let fields = parseCSVLine(line)

            // Skip a header row only when the first field isn't a valid date.
            // CIBC exports are headerless — dropping `index == 0` unconditionally
            // loses the first data row on those imports.
            if index == 0, let first = fields.first, !Self.isValidDateFormat(first) {
                continue
            }

            guard fields.count >= 4 else {
                throw BankCsvParserError.malformedRow(line: lineNumber, columnCount: fields.count)
            }

            let dateRaw = fields[0]
            guard Self.isValidDateFormat(dateRaw),
                  let date = dateFormatter.date(from: dateRaw) else {
                throw BankCsvParserError.invalidDate(line: lineNumber, raw: dateRaw)
            }

            let details = fields[1]
            if details.trimmingCharacters(in: .whitespaces).isEmpty {
                throw BankCsvParserError.emptyDetails(line: lineNumber)
            }

            let debit = try parseAmount(fields[2], line: lineNumber, field: "debit")
            let credit = try parseAmount(fields[3], line: lineNumber, field: "credit")

            if debit == 0.0 && credit == 0.0 {
                throw BankCsvParserError.zeroAmount(line: lineNumber)
            }

            let row = BankRow(date: date, details: details, debit: debit, credit: credit)
            parsed.append(ParsedRow(row: row, rawLine: line))
        }

        return parsed
    }

    private static let dateRegex = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")

    private static func isValidDateFormat(_ raw: String) -> Bool {
        let range = NSRange(raw.startIndex..., in: raw)
        return dateRegex.firstMatch(in: raw, range: range) != nil
    }

    private static func parseAmount(
        _ raw: String, line: Int, field: String
    ) throws -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0.0 }
        guard let value = Double(trimmed) else {
            throw BankCsvParserError.invalidNumber(line: line, field: field, raw: raw)
        }
        return value
    }

    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if inQuotes {
                if char == "\"" {
                    inQuotes = false
                } else {
                    current.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    fields.append(current)
                    current = ""
                default:
                    current.append(char)
                }
            }
        }
        fields.append(current)
        return fields
    }
}
